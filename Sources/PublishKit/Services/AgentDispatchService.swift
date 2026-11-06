import Foundation

@MainActor
public protocol DispatchServicing {
    func capabilities(for platform: PlatformID) -> ChannelCapabilities?
    func execute(request: ChannelRequest, execution: ChannelExecutionID, command: ChannelCommand, config: LLMConfig,
                 onEvent: @escaping @MainActor @Sendable (ChannelEvent) -> Void) async throws -> ChannelOutcome
    var workspaceID: Int? { get }
    func beginTask(id: UUID) async throws
    func handOff() async throws
    func resumeControl() async throws
}

@MainActor
public final class AgentDispatchService: DispatchServicing {
    private var taskID: UUID?
    private var sessions: [PlatformID: (request: ChannelRequest, outcome: ChannelOutcome)] = [:]
    private var activeAttempts: [PlatformID: UUID] = [:]
    private var bridges: [PlatformID: EgoBridge] = [:]
    private var spaceName = ""
    private var spaceID: Int?
    private var handedOff = false
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
        taskID = id; sessions = [:]
        spaceName = "inkpost \(UUID().uuidString)"
        bridges = [:]; spaceID = nil; handedOff = false
        registry = makeRegistry()
    }
    public func handOff() async throws {
        guard let id = spaceID else { throw EgoBridge.BridgeError.toolFailed("还没有可打开的浏览器工作区") }
        if handedOff { return }
        _ = try await EgoLiteEngine().runRaw(script: "const task = await taskSpace(\(id)); await task.handOff(); cliLog(JSON.stringify({ok:true}));")
        handedOff = true
    }
    public func resumeControl() async throws {
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
            let name = String(data: try JSONSerialization.data(withJSONObject: [spaceName]), encoding: .utf8)!
            let result = try await engine.runRaw(script: "const task = await taskSpace(\(name)[0]); const page = \(bridges.isEmpty ? "task.page(\"p1\")" : "await task.newPage()"); cliLog(JSON.stringify({label:page.label,spaceID:task.spaceId}));")
            guard let label = result.string("label") else { throw EgoBridge.BridgeError.noResult(result.rawOutput) }
            spaceID = result.json?["spaceID"] as? Int
            bridge = try EgoBridge(spaceName: spaceName, engine: engine, pageLabel: label)
            bridges[platform] = bridge
        }
        return bridge
    }

    public func execute(request: ChannelRequest, execution: ChannelExecutionID, command: ChannelCommand, config: LLMConfig,
                        onEvent: @escaping @MainActor @Sendable (ChannelEvent) -> Void) async throws -> ChannelOutcome {
        try Task.checkCancellation()
        guard taskID == execution.taskID, activeAttempts[execution.platform] == nil else {
            return .failed(.init(code: .invalidCommand, stage: .validatingRequest, detail: "任务不匹配或渠道正在执行", recovery: .notRecoverable))
        }
        let platform = execution.platform
        let previous = sessions[platform]
        guard command == .prepare ? previous == nil : (previous?.request == request && previous?.outcome.canResume == true) else {
            return .failed(.init(code: .invalidCommand, stage: .validatingRequest, detail: "无法以当前内容重复开始或恢复此渠道", recovery: .notRecoverable))
        }
        activeAttempts[platform] = execution.attemptID
        defer { if taskID == execution.taskID { activeAttempts[platform] = nil } }
        onEvent(.init(execution: execution, payload: .stage(.validatingRequest)))
        let context: ChannelExecutionContext
        do {
            let adapter = try requiredAdapter(platform)
            try PlatformRules.validate(request, capabilities: adapter.capabilities)
            if adapter.capabilities.requiresLLM && config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ChannelFailure(code: .configurationMissing, stage: .validatingRequest, detail: "缺少模型接口配置", recovery: .retryAllowed)
            }
            onEvent(.init(execution: execution, payload: .stage(.openingEditor)))
            let bridge = try await bridge(for: platform)
            guard taskID == execution.taskID else { throw CancellationError() }
            context = ChannelExecutionContext(execution: execution, command: command, bridge: bridge, config: config, onEvent: onEvent)
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
