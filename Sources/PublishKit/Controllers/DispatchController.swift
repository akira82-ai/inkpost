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
    @ObservationIgnored private let onCompletion: @MainActor (DispatchCompletion) -> Void
    @ObservationIgnored private var notificationWorkspaceID: Int?
    @ObservationIgnored private var openingNotificationSpaces: Set<Int> = []
    @ObservationIgnored private var draftRequest: ChannelRequest?
    @ObservationIgnored private var attempts: [PlatformID: UUID] = [:]
    @ObservationIgnored private var generation = UUID()

    public init(service: any DispatchServicing, settings: DispatchSettings, state: DispatchModel? = nil, onCompletion: @escaping @MainActor (DispatchCompletion) -> Void = { _ in }) {
        self.onCompletion = onCompletion
        self.state = state ?? DispatchModel()
        self.service = service
        self.settings = settings
        self.state.selectedPlatforms = settings.selectedPlatforms()
    }

    public var canDispatch: Bool {
        state.overallPhase == .pending && !state.isHandingOff && PlatformRules.canStart(body: state.markdown, selectedPlatforms: state.selectedPlatforms)
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
        guard state.overallPhase == .pending, path != target,
              let from = state.assetPaths.firstIndex(of: path),
              let to = state.assetPaths.firstIndex(of: target) else { return }
        state.assetPaths.remove(at: from)
        // Removing an earlier source shifts the target one slot to the left.
        state.assetPaths.insert(path, at: from < to ? to - 1 : to)
    }
    /// The sole result action prefers the first unfinished channel. A missing Page exposes
    /// workspace navigation on the same button, without treating navigation as successful filling.
    public func openTaskDestination() {
        guard state.overallPhase != .pending, state.overallPhase != .preparing, !state.isHandingOff else { return }
        guard !state.opensWorkspaceAfterMissingPage, let platform = state.attentionPlatforms.first else {
            openWorkspace()
            return
        }
        state.isHandingOff = true
        state.navigationMessage = nil
        let token = generation
        Task {
            defer { if generation == token { state.isHandingOff = false } }
            do {
                try await service.openChannel(platform)
            } catch {
                guard generation == token else { return }
                if case ChannelNavigationError.pageUnavailable = error {
                    state.opensWorkspaceAfterMissingPage = true
                    state.navigationMessage = "\(platform.title)页面不可用，请打开工作区查看。"
                } else {
                    state.navigationMessage = "未能打开渠道页面，内容已保留，请重试。"
                }
                log(error.localizedDescription)
            }
        }
    }

    public func openWorkspace() {
        guard state.overallPhase != .preparing, !state.isHandingOff else { return }
        state.isHandingOff = true
        let completed = state.overallPhase == .awaitingConfirm
        let token = generation
        state.navigationMessage = nil
        Task {
            defer { if generation == token { state.isHandingOff = false } }
            do {
                if let id = service.workspaceID { try await service.openWorkspace(id: id) }
                else { try await service.handOff() }
                guard generation == token else { return }
                if completed {
                    state.history.insert(DispatchRecord(title: state.title, markdown: state.markdown,
                        platforms: state.taskPlatforms, assetPaths: state.assetPaths,
                        assetData: state.assetData, workspaceID: service.workspaceID), at: 0)
                    state.isHandingOff = false
                    newDraft()
                    state.eventLog = []
                    state.platformPhase = [:]
                    state.notice = "上一份已交接，可以开始新一份内容"
                }
            } catch {
                guard generation == token else { return }
                state.navigationMessage = "未能打开工作区，内容已保留，请重试。"
                log(error.localizedDescription)
            }
        }
    }
    /// Notification navigation does not archive/reset content or alter another task's state.
    public func openNotificationWorkspace(taskID: UUID, workspaceID: Int) async {
        guard workspaceID > 0 else { state.notice = "通知中的工作区无效"; return }
        guard taskID != state.taskID || state.overallPhase != .preparing else {
            state.notice = "此任务仍在填写中，请完成后再打开工作区"
            return
        }
        guard openingNotificationSpaces.insert(workspaceID).inserted else { return }
        defer { openingNotificationSpaces.remove(workspaceID) }
        do { try await service.openWorkspace(id: workspaceID) }
        catch {
            state.notice = "未能打开通知对应的工作区，内容已保留，请重试"
            log("通知工作区 \(workspaceID)：\(error.localizedDescription)")
        }
    }
    public func resume(_ platform: PlatformID) {
        guard !state.isHandingOff, state.overallPhase != .preparing, state.platformOutcomes[platform]?.canResume == true, draftRequest != nil else { return }
        state.overallPhase = .preparing
        let token = generation
        runningTask = Task {
            do { try await service.resumeControl(); try await runOnePlatform(platform, command: .resumeAfterUser) }
            catch {
                guard generation == token else { return }
                if error is CancellationError || Task.isCancelled { state.platformPhase[platform] = .cancelled }
                else { apply(.failed(.init(code: .executionFailed, stage: .openingEditor, detail: error.localizedDescription, recovery: .retryAllowed)), to: platform) }
            }
            guard generation == token else { return }
            finishTask()
        }
    }
    private func finishTask() {
        state.currentPlatform = nil
        state.overallPhase = state.taskPlatforms.contains { state.platformPhase[$0] == .cancelled } ? .cancelled : (state.taskPlatforms.allSatisfy { state.platformPhase[$0] == .awaitingConfirm } ? .awaitingConfirm : .failed)
        let message = state.overallPhase == .cancelled ? "已停止处理，内容已保留，请检查浏览器页面" : (state.overallPhase == .awaitingConfirm ? "全部已填好，请检查并发布" : "部分渠道需要您手工处理")
        state.notice = message
        onCompletion(DispatchCompletion(taskID: state.taskID, workspaceID: notificationWorkspaceID,
            phase: state.overallPhase, platforms: state.taskPlatforms, phases: state.platformPhase,
            failures: state.platformOutcomes.compactMapValues(\.failure)))
    }
    // MARK: - 分发

    public func dispatch() {
        guard canDispatch else { return }
        state.overallPhase = .preparing
        notificationWorkspaceID = nil
        state.errorMessage = nil
        state.eventLog = []
        state.platformOutcomes = [:]; state.platformEvents = [:]; attempts = [:]
        for p in state.selectedPlatforms { state.platformPhase[p] = .pending }

        let platforms = state.selectedPlatforms
        state.taskPlatforms = platforms
        generation = UUID()
        let token = generation
        state.taskID = token
        draftRequest = ChannelRequest(title: state.title, body: state.markdown,
                                      assets: state.assetPaths)
        runningTask = Task {
            await notifier.prepare()
            do {
                try await service.beginTask(id: token)
                guard generation == token else { return }
                notificationWorkspaceID = service.workspaceID
            } catch {
                guard generation == token else { return }
                let cancelled = error is CancellationError || Task.isCancelled
                if !cancelled { state.errorMessage = error.localizedDescription }
                for p in platforms {
                    state.platformPhase[p] = cancelled ? .cancelled : .failed
                    state.platformMessages[p] = cancelled ? "已取消" : error.localizedDescription
                }
                finishTask(); return
            }
            for p in platforms {
                guard token == generation else { return }
                if Task.isCancelled {
                    for pending in platforms where state.platformPhase[pending] == .pending { state.platformPhase[pending] = .cancelled }
                    break
                }
                do {
                    try await runOnePlatform(p)
                } catch {
                    guard generation == token else { return }
                    if error is CancellationError || Task.isCancelled {
                        state.platformPhase[p] = .cancelled
                        for pending in platforms where state.platformPhase[pending] == .pending { state.platformPhase[pending] = .cancelled }
                        break
                    }
                    apply(.failed(.init(code: .executionFailed, stage: .openingEditor, detail: error.localizedDescription, recovery: .retryAllowed)), to: p)
                }
            }
            guard generation == token else { return }
            finishTask()
            if platforms.allSatisfy({ state.platformPhase[$0] == .awaitingConfirm || state.platformPhase[$0] == .needLogin }) {
                log("全部平台处理完毕。请在 ego 浏览器逐个检查草稿并亲手发布。")
            }
        }
    }

    func runOnePlatform(_ platform: PlatformID, command: ChannelCommand = .prepare) async throws {
        guard let request = draftRequest else { return }
        let execution = ChannelExecutionID(taskID: generation, platform: platform)
        attempts[platform] = execution.attemptID
        defer {
            if generation == execution.taskID { notificationWorkspaceID = service.workspaceID }
            if attempts[platform] == execution.attemptID { attempts[platform] = nil }
        }
        state.currentPlatform = platform
        state.platformPhase[platform] = .preparing
        let outcome = try await service.execute(request: request, execution: execution, command: command,
            onEvent: { [weak self] event in self?.receive(event) })
        try Task.checkCancellation()
        guard generation == execution.taskID, attempts[platform] == execution.attemptID else { return }
        attempts[platform] = nil
        apply(outcome, to: platform)
    }

    func receive(_ event: ChannelEvent) {
        guard event.execution.taskID == generation,
              attempts[event.execution.platform] == event.execution.attemptID,
              state.platformPhase[event.execution.platform] == .preparing else { return }
        state.platformEvents[event.execution.platform] = event
        if case .diagnostic(let message) = event.payload { log(message) }
    }

    private func apply(_ outcome: ChannelOutcome, to platform: PlatformID) {
        state.platformOutcomes[platform] = outcome
        switch outcome {
        case .readyForReview(let message):
            state.platformPhase[platform] = .awaitingConfirm
            state.platformMessages[platform] = message
        case .waitingForUser(let failure):
            state.platformPhase[platform] = failure.recovery == .loginRequired ? .needLogin : .failed
            state.platformMessages[platform] = failure.detail
        case .failed(let failure):
            state.platformPhase[platform] = .failed
            state.platformMessages[platform] = failure.detail
        }
        if let failure = outcome.failure { log("[\(platform.rawValue)] \(failure.code.rawValue) / \(failure.stage.rawValue) / \(failure.diagnosticID): \(failure.detail)") }
    }

    public func cancel() {
        guard state.overallPhase == .preparing else { return }
        runningTask?.cancel()
    }

    public func editUnfinishedChannels() {
        guard !state.isHandingOff, [.failed, .cancelled].contains(state.overallPhase) else { return }
        let unfinished = state.taskPlatforms.filter { state.platformPhase[$0] != .awaitingConfirm }
        reset()
        state.selectedPlatforms = unfinished
    }
    public func newDraft() {
        guard state.overallPhase == .awaitingConfirm else { return }
        reset()
        state.title = ""; state.markdown = ""
        state.assetPaths = []; state.assetData = [:]
    }
    public func reset() {
        guard state.overallPhase != .preparing, !state.isHandingOff else { return }
        generation = UUID()
        runningTask?.cancel()
        state.currentPlatform = nil
        state.platformMessages = [:]
        state.platformOutcomes = [:]; state.platformEvents = [:]; attempts = [:]
        state.taskPlatforms = []
        state.taskID = nil
        notificationWorkspaceID = nil
        draftRequest = nil
        state.overallPhase = .pending
        state.errorMessage = nil
        state.navigationMessage = nil
        state.opensWorkspaceAfterMissingPage = false
        for p in state.selectedPlatforms { state.platformPhase[p] = .pending }
    }
}

