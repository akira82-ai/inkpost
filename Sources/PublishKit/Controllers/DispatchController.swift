import Foundation
import Observation

@MainActor
@Observable
public final class DispatchController {
    public let state: DispatchModel
    @ObservationIgnored private var runningTask: Task<Void, Never>?
    @ObservationIgnored private let service: any DispatchServicing
    @ObservationIgnored private let settings: DispatchSettings
    @ObservationIgnored private let assets = AssetService()
    @ObservationIgnored private let notifier = CompletionNotifier()
    @ObservationIgnored private var draftRequest: ChannelRequest?
    @ObservationIgnored private var draftTitle = ""
    @ObservationIgnored private var draftBody = ""
    @ObservationIgnored private var draftImageCount = 0
    @ObservationIgnored private var taskConfig: LLMConfig?
    @ObservationIgnored private var generation = UUID()

    public init(service: any DispatchServicing, settings: DispatchSettings, state: DispatchModel? = nil) {
        self.state = state ?? DispatchModel()
        self.service = service
        self.settings = settings
        let config = settings.load()
        self.state.apiKey = config.apiKey
        self.state.model = config.model
        self.state.selectedPlatforms = settings.selectedPlatforms()
    }

    public var requiresModelConfiguration: Bool {
        state.selectedPlatforms.contains { service.capabilities(for: $0)?.requiresLLM != false }
    }

    public var canDispatch: Bool {
        state.overallPhase == .pending && !state.isHandingOff && !state.selectedPlatforms.isEmpty && (!state.selectedPlatforms.contains(where: { service.capabilities(for: $0)?.usesTitle == true }) || !state.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) && !state.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (!requiresModelConfiguration || !state.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    public func saveConfig() {
        settings.save(apiKey: state.apiKey, model: state.model)
    }

    func log(_ line: String) {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"
        state.eventLog.append("[\(df.string(from: Date()))] \(line)")
        if state.eventLog.count > 300 { state.eventLog.removeFirst(state.eventLog.count - 300) }
    }

    public func addAssets(_ paths: [String]) {
        guard state.overallPhase == .pending else { return }
        var added = 0, duplicate = 0, overflow = 0
        var errors: [String] = []
        for path in paths {
            do {
                if let imported = try assets.importFile(path, existing: state.assetPaths) {
                    let preview = try assets.previewData(imported)
                    state.assetPaths.append(imported); state.assetData[imported] = preview; added += 1
                } else { duplicate += 1 }
            } catch AssetImportError.limitReached { overflow += 1 }
            catch { errors.append("\(URL(fileURLWithPath: path).lastPathComponent)：\(error.localizedDescription)") }
        }
        var messages: [String] = []
        if added > 0 { messages.append("已添加 \(added) 张图片") }
        if duplicate > 0 { messages.append(duplicate == 1 ? "该图片已经添加" : "\(duplicate) 张图片已经添加") }
        if overflow > 0 { messages.append("最多 6 张，\(overflow) 张未添加") }
        messages.append(contentsOf: errors)
        if !messages.isEmpty { state.notice = messages.joined(separator: "；") }
    }

    public func pasteImage(_ data: Data) {
        guard state.overallPhase == .pending else { return }
        do {
            if let path = try assets.importData(data, existing: state.assetPaths) { state.assetPaths.append(path); state.assetData[path] = try assets.previewData(path); state.notice = "图片已添加" }
            else { state.notice = "该图片已经添加" }
        } catch { state.notice = error.localizedDescription }
    }
    public func select(_ platform: PlatformID) {
        guard state.overallPhase == .pending else { return }
        if state.selectedPlatforms.contains(platform) { state.selectedPlatforms.removeAll { $0 == platform } }
        else { state.selectedPlatforms.append(platform) }
        settings.savePlatforms(state.selectedPlatforms)
    }
    public func removeAsset(_ path: String) {
        guard state.overallPhase == .pending else { return }
        state.assetPaths.removeAll { $0 == path }
        state.assetData[path] = nil
    }
    public func moveAsset(_ path: String, before target: String) {
        guard state.overallPhase == .pending, let from = state.assetPaths.firstIndex(of: path), let to = state.assetPaths.firstIndex(of: target) else { return }
        state.assetPaths.remove(at: from); state.assetPaths.insert(path, at: to)
    }
    public func openWorkspace() {
        guard state.overallPhase != .preparing, !state.isHandingOff else { return }
        state.isHandingOff = true
        let completed = state.overallPhase == .awaitingConfirm
        Task {
            defer { state.isHandingOff = false }
            do {
                try await service.handOff()
                if completed {
                    state.history.insert(DispatchRecord(title: state.title, markdown: state.markdown,
                        tags: state.tagsText, platforms: state.taskPlatforms, assetPaths: state.assetPaths,
                        assetData: state.assetData, workspaceID: service.workspaceID), at: 0)
                    newDraft()
                    state.eventLog = []
                    state.platformPhase = [:]
                    state.notice = "上一份已交接，可以开始新一份内容"
                }
            } catch { state.notice = "未能打开工作区，内容已保留，请重试"; log(error.localizedDescription) }
        }
    }
    public func resume(_ platform: PlatformID) {
        guard state.overallPhase != .preparing, [.failed, .needLogin].contains(state.platformPhase[platform] ?? .pending), taskConfig != nil else { return }
        state.overallPhase = .preparing
        let token = generation
        runningTask = Task {
            do { try await service.resumeControl(); try await runOnePlatform(platform) }
            catch { guard generation == token else { return }; state.platformPhase[platform] = .failed; state.platformMessages[platform] = error.localizedDescription }
            guard generation == token else { return }
            finishTask()
        }
    }
    private func finishTask() {
        state.currentPlatform = nil
        state.overallPhase = state.taskPlatforms.allSatisfy { state.platformPhase[$0] == .awaitingConfirm } ? .awaitingConfirm : .failed
        let message = state.overallPhase == .awaitingConfirm ? "全部已填好，请检查并发布" : "部分渠道需要您手工处理"
        state.notice = message
        Task { await notifier.deliver(message) }
    }
    // MARK: - 分发

    public func dispatch() {
        saveConfig()
        guard canDispatch else { return }
        state.overallPhase = .preparing
        state.errorMessage = nil
        state.eventLog = []
        state.manualReceipt = ""
        for p in state.selectedPlatforms { state.platformPhase[p] = .pending }

        let platforms = state.selectedPlatforms
        state.taskPlatforms = platforms
        generation = UUID()
        let token = generation
        taskConfig = LLMConfig(baseURL: DispatchSettings.baseURL, apiKey: state.apiKey, model: state.model)
        let html = MarkdownLite.render(state.markdown)
        let plain = MarkdownLite.plain(state.markdown)
        draftTitle = state.title; draftBody = plain; draftImageCount = state.assetPaths.count
        let tags = state.tagsText
            .split(whereSeparator: { $0.isWhitespace })
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "#")) }
            .filter { !$0.isEmpty }
        let assets = state.assetPaths

        draftRequest = ChannelRequest(title: state.title, body: plain, html: html, tags: tags, assets: assets)
        runningTask = Task {
            await notifier.prepare()
            do { try await service.beginTask() } catch {
                state.errorMessage = error.localizedDescription
                for p in platforms { state.platformPhase[p] = .failed; state.platformMessages[p] = error.localizedDescription }
                finishTask(); return
            }
            for p in platforms {
                if Task.isCancelled || token != generation { return }
                do {
                    try await runOnePlatform(p)
                } catch {
                    guard generation == token else { return }
                    state.platformPhase[p] = .failed
                    state.platformMessages[p] = error.localizedDescription
                    log("【\(p.title)】✗ 异常：\(error.localizedDescription)")
                }
            }
            guard generation == token else { return }
            finishTask()
            if platforms.allSatisfy({ state.platformPhase[$0] == .awaitingConfirm || state.platformPhase[$0] == .needLogin }) {
                log("全部平台处理完毕。请在 ego 浏览器逐个检查草稿并亲手发布（即刻的弹窗别关）。")
            }
        }
    }

    func runOnePlatform(_ p: PlatformID) async throws {
        state.currentPlatform = p
        state.platformPhase[p] = .preparing
        let result = try await service.prepare(platform: p,
            request: draftRequest!,
            config: taskConfig!,
            onEvent: { [weak self] msg in
                Task { @MainActor in self?.log("【\(p.title)】\(msg)") }
            })
        try Task.checkCancellation()
        state.platformMessages[p] = result.message
        switch result.status {
        case "draftReady":
            try await service.verifyDraft(platform: p, result: result, title: draftTitle, body: draftBody, imageCount: draftImageCount)
            state.platformPhase[p] = .awaitingConfirm
            log("【\(p.title)】✅ 草稿就绪：\(result.message)")
        case "needLogin":
            state.platformPhase[p] = .needLogin
            log("【\(p.title)】⚠️ 需要登录：请在 ego lite 打开\(p.title)登录后重试该平台")
        default:
            state.platformPhase[p] = .failed
            log("【\(p.title)】✗ 失败：\(result.message)")
        }
    }

    /// fixture 回执回读；真实平台请手动粘贴发布链接
    public func readFixtureReceipt(for p: PlatformID) {
        Task {
            do {
                let url = try await service.readReceipt(for: p)
                if !url.isEmpty {
                    state.manualReceipt = url
                    log("✅ 回执：\(url)")
                } else {
                    state.errorMessage = "未读取到回执：请在 fixture 页面点「确认发布」后重试"
                }
            } catch {
                state.errorMessage = error.localizedDescription
            }
        }
    }

    public func editUnfinishedChannels() {
        guard state.overallPhase == .failed else { return }
        let unfinished = state.taskPlatforms.filter { state.platformPhase[$0] != .awaitingConfirm }
        reset()
        state.selectedPlatforms = unfinished
    }
    public func newDraft() {
        guard state.overallPhase == .awaitingConfirm else { return }
        reset()
        state.title = ""; state.markdown = ""; state.tagsText = ""
        state.assetPaths = []; state.assetData = [:]
    }
    public func reset() {
        guard state.overallPhase != .preparing else { return }
        generation = UUID()
        runningTask?.cancel()
        state.currentPlatform = nil
        state.platformMessages = [:]
        state.taskPlatforms = []
        draftRequest = nil
        taskConfig = nil
        state.overallPhase = .pending
        state.errorMessage = nil
        state.manualReceipt = ""
        for p in state.selectedPlatforms { state.platformPhase[p] = .pending }
    }
}

