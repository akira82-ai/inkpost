import Foundation

@MainActor
public protocol DispatchServicing {
    func capabilities(for platform: PlatformID) -> ChannelCapabilities?
    func execute(request: ChannelRequest, execution: ChannelExecutionID, command: ChannelCommand,
                 onEvent: @escaping @MainActor @Sendable (ChannelEvent) -> Void) async throws -> ChannelOutcome
    var workspaceID: Int? { get }
    func beginTask(id: UUID) async throws
    func handOff() async throws
    func completeTask() async throws
    func resumeControl() async throws
    func openWorkspace(id: Int) async throws
    func openChannel(_ platform: PlatformID) async throws
}

public enum ChannelNavigationError: Error, Equatable {
    case pageUnavailable
}

public extension DispatchServicing {
    func completeTask() async throws { try await handOff() }

    func openChannel(_ platform: PlatformID) async throws {
        throw ChannelNavigationError.pageUnavailable
    }

    func openWorkspace(id: Int) async throws {
        guard workspaceID == id else { throw EgoBridge.BridgeError.toolFailed("通知对应的工作区无法打开") }
        try await handOff()
    }
}

@MainActor
public final class DispatchService: DispatchServicing {
    private var taskID: UUID?
    private var taskRequest: ChannelRequest?
    private var assetPreparation: Task<PreparedAssetBatch, Error>?
    private var sessions: [PlatformID: (request: ChannelRequest, outcome: ChannelOutcome)] = [:]
    private var activeAttempts: [PlatformID: UUID] = [:]
    private var bridges: [PlatformID: EgoBridge] = [:]
    private var spaceID: Int?
    private var handedOff = false
    private var completed = false
    private var completedPageURLs: [String: String] = [:]
    private var registry: ChannelRegistry
    private let makeRegistry: () -> ChannelRegistry
    private var bridgeFactory: ((PlatformID) async throws -> EgoBridge)?
    public var workspaceID: Int? { spaceID }
    public init(registryFactory: @escaping () -> ChannelRegistry = { .standard }) {
        makeRegistry = registryFactory; registry = registryFactory()
    }
    init(registryFactory: @escaping () -> ChannelRegistry, bridgeFactory: @escaping (PlatformID) async throws -> EgoBridge) {
        makeRegistry = registryFactory; registry = registryFactory(); self.bridgeFactory = bridgeFactory
    }
    public func beginTask(id: UUID) async throws {
        guard activeAttempts.isEmpty else { throw ChannelFailure(code: .invalidCommand, stage: .validatingRequest, detail: "仍有渠道执行中", recovery: .notRecoverable) }
        assetPreparation?.cancel()
        assetPreparation = nil; taskRequest = nil
        taskID = id; sessions = [:]
        bridges = [:]; spaceID = nil; handedOff = false; completed = false; completedPageURLs = [:]
        registry = makeRegistry()
        if bridgeFactory == nil {
            let window = try await EgoWorkspaceNavigator.currentWindow()
            let script = try EgoWorkspaceNavigator.claimCurrentSpaceScript(windowID: window.id, title: window.title)
            let result = try await EgoLiteEngine().runRaw(script: script)
            guard result.bool("ok") == true, let id = result.json?["spaceID"] as? Int, id >= 0 else {
                throw EgoBridge.BridgeError.noResult(result.rawOutput)
            }
            spaceID = id
        }
    }
    public func handOff() async throws {
        guard let id = spaceID else { throw EgoBridge.BridgeError.toolFailed("还没有可打开的浏览器工作区") }
        if handedOff { return }
        _ = try await EgoLiteEngine().runRaw(script: "const task = await taskSpace(\(id)); await task.handOff(); cliLog(JSON.stringify({ok:true}));")
        handedOff = true
    }
    /// Complete the Agent task while preserving every task Page for manual publishing.
    public func completeTask() async throws {
        guard !completed, let id = spaceID else { return }
        guard activeAttempts.isEmpty else { throw EgoBridge.BridgeError.toolFailed("渠道仍在执行，不能完成工作区") }
        let result = try await EgoLiteEngine().runRaw(script: """
        const info = (await listTaskSpaces()).find(space => space.id === \(id));
        if (!info) throw new Error("本次任务工作区已不存在");
        if (info.ownership === "user") {
            cliLog(JSON.stringify({ok:true, urls:{}}));
        } else {
            const task = await \(handedOff ? "takeOverTaskSpace" : "taskSpace")(\(id));
            const tabs = await task.tabs();
            const urls = Object.fromEntries(tabs.filter(tab => tab.label).map(tab => [tab.label, tab.url]));
            await task.finish({keep:"all"});
            cliLog(JSON.stringify({ok:true, urls}));
        }
        """)
        guard result.bool("ok") == true else { throw EgoBridge.BridgeError.noResult(result.rawOutput) }
        completedPageURLs = result.json?["urls"] as? [String: String] ?? [:]
        completed = true
        handedOff = true
    }

    /// Final actions only activate ego; they never select, claim or switch a Space.
    public func openWorkspace(id: Int) async throws {
        guard id >= 0 else { throw EgoBridge.BridgeError.toolFailed("无效的浏览器工作区") }
        guard activeAttempts.isEmpty else {
            throw EgoBridge.BridgeError.toolFailed("仍在填写中，请完成后再打开")
        }
        try await EgoWorkspaceNavigator.activate()
    }

    /// Finished tasks lose Page labels. Resolve a unique original URL, never an arbitrary tab.
    public func openChannel(_ platform: PlatformID) async throws {
        guard activeAttempts.isEmpty else { throw EgoBridge.BridgeError.toolFailed("此工作区仍在填写中，请完成后再打开") }
        guard let id = spaceID, let bridge = bridges[platform] else { throw ChannelNavigationError.pageUnavailable }
        let identity = String(data: try JSONSerialization.data(withJSONObject: ["label": bridge.pageLabel,
            "url": completedPageURLs[bridge.pageLabel] ?? ""]), encoding: .utf8)!
        let result = try await EgoLiteEngine().runRaw(script: """
        const info = (await listTaskSpaces()).find(space => space.id === \(id));
        if (!info) throw new Error("本次任务工作区已不存在");
        const wasCompleted = info.ownership === "user";
        const task = await (wasCompleted ? claimTaskSpace : \(handedOff ? "takeOverTaskSpace" : "taskSpace"))(\(id));
        const identity = \(identity);
        let missing = false;
        let navigationError = null;
        try {
            const tabs = await task.tabs();
            const matches = \(completed ? "true" : "false")
                ? tabs.filter(tab => identity.url && tab.url === identity.url)
                : tabs.filter(tab => tab.label === identity.label);
            if (matches.length !== 1) { missing = true; }
            else {
                const tab = matches[0];
                const page = tab.label ? task.page(tab.label) : await task.adopt(tab.page);
                await page.cdp("Page.bringToFront");
                const active = (await task.tabs()).find(tab => tab.active);
                if (active?.targetId !== tab.targetId) throw new Error("目标渠道页面未激活");
            }
        } catch (error) { navigationError = String(error); }
        finally {
            if (wasCompleted) await task.finish({keep:"all"});
            else await task.handOff();
        }
        cliLog(JSON.stringify({ok: !missing && !navigationError, missing, navigationError}));
        """)
        handedOff = true
        if result.bool("missing") == true { throw ChannelNavigationError.pageUnavailable }
        if let error = result.string("navigationError") { throw EgoBridge.BridgeError.toolFailed(error) }
        guard result.bool("ok") == true else { throw EgoBridge.BridgeError.noResult(result.rawOutput) }
        try await EgoWorkspaceNavigator.activate()
    }

    public func resumeControl() async throws {
        guard !completed else { throw EgoBridge.BridgeError.toolFailed("此任务已经结束，不能继续填写") }
        guard handedOff, let id = spaceID else { return }
        _ = try await EgoLiteEngine().runRaw(script: "const task = await takeOverTaskSpace(\(id)); cliLog(JSON.stringify({ok:true}));")
        handedOff = false
    }

    public func capabilities(for platform: PlatformID) -> ChannelCapabilities? { registry.adapter(for: platform)?.capabilities }
    private func requiredAdapter(_ platform: PlatformID) throws -> any ChannelAdapter {
        guard let adapter = registry.adapter(for: platform) else {
            throw ChannelFailure(code: .invalidCommand, stage: .validatingRequest, detail: "渠道未注册：\(platform.rawValue)", recovery: .notRecoverable)
        }
        return adapter
    }

    private func bridge(for platform: PlatformID) async throws -> EgoBridge {
        guard taskID != nil else { throw ChannelFailure(code: .invalidCommand, stage: .validatingRequest, detail: "任务尚未开始", recovery: .notRecoverable) }
        let bridge: EgoBridge
        if let existing = bridges[platform] { bridge = existing }
        else if let bridgeFactory {
            bridge = try await bridgeFactory(platform)
            bridges[platform] = bridge
        } else {
            let engine = try EgoLiteEngine()
            guard let id = spaceID else { throw EgoBridge.BridgeError.toolFailed("尚未连接 ego 当前空间") }
            let result = try await engine.runRaw(script: "const task = await taskSpace(\(id)); const page = await task.newPage(); cliLog(JSON.stringify({label:page.label}));")
            guard let label = result.string("label") else { throw EgoBridge.BridgeError.noResult(result.rawOutput) }
            bridge = try EgoBridge(spaceName: "", engine: engine, pageLabel: label, spaceID: id)
            bridges[platform] = bridge
        }
        return bridge
    }

    public func execute(request: ChannelRequest, execution: ChannelExecutionID, command: ChannelCommand,
                        onEvent: @escaping @MainActor @Sendable (ChannelEvent) -> Void) async throws -> ChannelOutcome {
        try Task.checkCancellation()
        guard taskID == execution.taskID, activeAttempts[execution.platform] == nil else {
            return .failed(.init(code: .invalidCommand, stage: .validatingRequest, detail: "任务不匹配或渠道正在执行", recovery: .notRecoverable))
        }
        let platform = execution.platform
        guard taskRequest == nil || taskRequest == request else {
            return .failed(.init(code: .invalidCommand, stage: .validatingRequest, detail: "任务输入快照已改变", recovery: .notRecoverable))
        }
        let previous = sessions[platform]
        guard command == .prepare ? previous == nil : (previous?.request == request && previous?.outcome.canResume == true) else {
            return .failed(.init(code: .invalidCommand, stage: .validatingRequest, detail: "无法以当前内容重复开始或恢复此渠道", recovery: .notRecoverable))
        }
        activeAttempts[platform] = execution.attemptID
        defer { if taskID == execution.taskID { activeAttempts[platform] = nil } }
        onEvent(.init(execution: execution, payload: .stage(.validatingRequest)))
        let context: ChannelExecutionContext
        do {
            _ = try requiredAdapter(platform)
            if assetPreparation == nil {
                taskRequest = request
                onEvent(.init(execution: execution, payload: .diagnostic("统一准备 \(request.assets.count) 张 PNG 上传素材")))
                assetPreparation = Task.detached { try AssetService.preparePNGAssets(request.assets) }
            }
            let preparation = assetPreparation!
            let batch = try await withTaskCancellationHandler {
                try await preparation.value
            } onCancel: { preparation.cancel() }
            try Task.checkCancellation()
            guard taskID == execution.taskID else { throw CancellationError() }
            onEvent(.init(execution: execution, payload: .stage(.openingEditor)))
            let bridge = try await bridge(for: platform)
            guard taskID == execution.taskID else { throw CancellationError() }
            context = ChannelExecutionContext(execution: execution, command: command, bridge: bridge, preparedAssets: batch.assets, onEvent: onEvent)
        } catch {
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            let failure = (error as? ChannelFailure) ?? .init(code: .executionFailed, stage: .openingEditor, detail: error.localizedDescription, recovery: .retryAllowed)
            let outcome = ChannelOutcome.failed(failure)
            if taskID == execution.taskID { sessions[platform] = (request, outcome) }
            return outcome
        }
        defer { context.finish() }
        var outcome: ChannelOutcome
        do {
            outcome = try await requiredAdapter(platform).execute(request: request, context: context)
            try Task.checkCancellation()
        } catch {
            if error is CancellationError || Task.isCancelled {
                if taskID == execution.taskID {
                    sessions[platform] = (request, .failed(.init(code: .operationResultUnknown, stage: context.stage, detail: "执行已取消，请检查页面后继续", recovery: .inspectionRequired)))
                }
                throw CancellationError()
            }
            outcome = .failed(context.mapFailure(error))
        }
        guard taskID == execution.taskID else { throw CancellationError() }
        sessions[platform] = (request, outcome)
        return outcome
    }
}
