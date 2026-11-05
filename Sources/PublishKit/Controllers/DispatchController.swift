import Foundation
import Observation

@MainActor
@Observable
public final class DispatchController {
    public let state: DispatchModel
    @ObservationIgnored private var runningTask: Task<Void, Never>?
    @ObservationIgnored private let service: any DispatchServicing
    @ObservationIgnored private let settings: DispatchSettings

    public init(service: any DispatchServicing, settings: DispatchSettings, state: DispatchModel? = nil) {
        self.state = state ?? DispatchModel()
        self.service = service
        self.settings = settings
        let config = settings.load()
        self.state.apiKey = config.apiKey
        self.state.model = config.model
    }

    public var canDispatch: Bool {
        state.overallPhase != .preparing && !state.selectedPlatforms.isEmpty && !state.title.isEmpty && !state.markdown.isEmpty && !state.apiKey.isEmpty
    }

    func saveConfig() {
        settings.save(apiKey: state.apiKey, model: state.model)
    }

    func log(_ line: String) {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"
        state.eventLog.append("[\(df.string(from: Date()))] \(line)")
        if state.eventLog.count > 300 { state.eventLog.removeFirst(state.eventLog.count - 300) }
    }

    public func addAssets(_ paths: [String]) {
        state.assetPaths.append(contentsOf: paths)
    }

    // MARK: - 分发

    public func dispatch() {
        saveConfig()
        guard canDispatch else { return }
        state.overallPhase = .preparing
        state.errorMessage = nil
        state.eventLog = []
        state.manualReceipt = ""
        for p in state.selectedPlatforms { state.platformPhase[p] = .preparing }

        let platforms = state.selectedPlatforms
        let html = MarkdownLite.render(state.markdown)
        let plain = MarkdownLite.plain(state.markdown)
        let tags = state.tagsText
            .split(whereSeparator: { $0.isWhitespace })
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "#")) }
            .filter { !$0.isEmpty }
        let assets = state.assetPaths

        runningTask = Task {
            defer { if state.overallPhase == .preparing { state.overallPhase = .awaitingConfirm } }
            for p in platforms {
                if Task.isCancelled { break }
                do {
                    try await runOnePlatform(p, html: html, plain: plain, tags: tags, assets: assets)
                } catch {
                    state.platformPhase[p] = .failed
                    log("【\(p.title)】✗ 异常：\(error.localizedDescription)")
                }
            }
            if platforms.allSatisfy({ state.platformPhase[$0] == .awaitingConfirm || state.platformPhase[$0] == .needLogin }) {
                log("全部平台处理完毕。请在 ego 浏览器逐个检查草稿并亲手发布（即刻的弹窗别关）。")
            }
        }
    }

    func runOnePlatform(_ p: PlatformID, html: String, plain: String, tags: [String], assets: [String]) async throws {
        let result = try await service.prepare(platform: p,
            goal: PlatformRules.goal(for: p, title: state.title, html: html, plain: plain, tags: tags, assets: assets),
            config: LLMConfig(baseURL: DispatchSettings.baseURL, apiKey: state.apiKey, model: state.model),
            onEvent: { [weak self] msg in
                Task { @MainActor in self?.log("【\(p.title)】\(msg)") }
            })
        switch result.status {
        case "draftReady":
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

    public func reset() {
        runningTask?.cancel()
        state.overallPhase = .pending
        state.errorMessage = nil
        state.manualReceipt = ""
        for p in state.selectedPlatforms { state.platformPhase[p] = .pending }
    }
}

