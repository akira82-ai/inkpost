import Foundation

@MainActor
public protocol DispatchServicing {
    func capabilities(for platform: PlatformID) -> ChannelCapabilities?
    func prepare(platform: PlatformID, request: ChannelRequest, config: LLMConfig,
                 onEvent: @escaping @Sendable (String) -> Void) async throws -> EgoBridge.Finish
    func prepare(platform: PlatformID, goal: String, config: LLMConfig,
                 onEvent: @escaping @Sendable (String) -> Void) async throws -> EgoBridge.Finish
    func prepare(platform: PlatformID, goal: String, body: String, tags: [String], assets: [String], config: LLMConfig,
                 onEvent: @escaping @Sendable (String) -> Void) async throws -> EgoBridge.Finish
    func verifyDraft(platform: PlatformID, result: EgoBridge.Finish, title: String, body: String, imageCount: Int) async throws
    var workspaceID: Int? { get }
    func beginTask() async throws
    func handOff() async throws
    func resumeControl() async throws
    func readReceipt(for platform: PlatformID) async throws -> String
}

public extension DispatchServicing {
    func capabilities(for platform: PlatformID) -> ChannelCapabilities? { ChannelRegistry.standard.adapter(for: platform)?.capabilities }
    func prepare(platform: PlatformID, request: ChannelRequest, config: LLMConfig,
                 onEvent: @escaping @Sendable (String) -> Void) async throws -> EgoBridge.Finish {
        try await prepare(platform: platform, goal: PlatformRules.goal(for: platform, title: request.title, html: request.html, plain: request.body, tags: request.tags, assets: request.assets), body: request.body, tags: request.tags, assets: request.assets, config: config, onEvent: onEvent)
    }
    func prepare(platform: PlatformID, goal: String, body: String, tags: [String], assets: [String], config: LLMConfig,
                 onEvent: @escaping @Sendable (String) -> Void) async throws -> EgoBridge.Finish {
        try await prepare(platform: platform, goal: goal, config: config, onEvent: onEvent)
    }
    var workspaceID: Int? { nil }
    func verifyDraft(platform: PlatformID, result: EgoBridge.Finish, title: String, body: String, imageCount: Int) async throws {}
    func beginTask() async throws {}
    func handOff() async throws { throw EgoBridge.BridgeError.toolFailed("当前服务无法打开工作区") }
    func resumeControl() async throws {}
}

@MainActor
public final class AgentDispatchService: DispatchServicing {
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
    init(workspaceName: String) { registry = .standard; makeRegistry = { .standard }; spaceName = workspaceName }
    init(registryFactory: @escaping () -> ChannelRegistry, bridgeFactory: @escaping (PlatformID) async throws -> EgoBridge) {
        makeRegistry = registryFactory; registry = registryFactory(); self.bridgeFactory = bridgeFactory
    }
    public func beginTask() async throws {
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

    public func prepare(platform: PlatformID, goal: String, config: LLMConfig,
                        onEvent: @escaping @Sendable (String) -> Void) async throws -> EgoBridge.Finish {
        let adapter = try requiredAdapter(platform)
        guard adapter.capabilities.requiresLLM else { throw EgoBridge.BridgeError.toolFailed("此渠道必须使用结构化正文和图片任务入口") }
        return try await prepare(platform: platform, request: .init(title: "", body: "", legacyGoal: goal), config: config, onEvent: onEvent)
    }

    public func capabilities(for platform: PlatformID) -> ChannelCapabilities? { registry.adapter(for: platform)?.capabilities }
    private func requiredAdapter(_ platform: PlatformID) throws -> any ChannelAdapter {
        guard let adapter = registry.adapter(for: platform) else { throw EgoBridge.BridgeError.toolFailed("渠道未注册：\(platform.rawValue)") }
        return adapter
    }

    private func bridge(for platform: PlatformID) async throws -> EgoBridge {
        if spaceName.isEmpty { try await beginTask() }
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

    public func prepare(platform: PlatformID, goal: String, body: String, tags: [String], assets: [String], config: LLMConfig,
                        onEvent: @escaping @Sendable (String) -> Void) async throws -> EgoBridge.Finish {
        try await prepare(platform: platform, request: .init(title: "", body: body, tags: tags, assets: assets, legacyGoal: goal), config: config, onEvent: onEvent)
    }

    public func prepare(platform: PlatformID, request: ChannelRequest, config: LLMConfig,
                        onEvent: @escaping @Sendable (String) -> Void) async throws -> EgoBridge.Finish {
        if spaceName.isEmpty { try await beginTask() }
        let adapter = try requiredAdapter(platform)
        guard request.assets.count <= adapter.capabilities.maximumImages else {
            throw EgoBridge.BridgeError.toolFailed("图片超过渠道允许的数量（\(adapter.capabilities.maximumImages) 张）")
        }
        let bridge = try await bridge(for: platform)
        return try await adapter.prepare(request: request, bridge: bridge, config: config, onEvent: onEvent)
    }

    /// GUI 与 CLI 共用的 Agent 执行入口，支持脚本化模型验证。
    public static func run(llm: any LLMSession, bridge: EgoBridge, goal: String,
                           onEvent: @escaping @Sendable (String) -> Void) async throws -> EgoBridge.Finish {
        let loop = AgentLoop(llm: llm, bridge: bridge, maxSteps: 20)
        loop.onEvent = onEvent
        return try await loop.run(goal: goal)
    }

    public func verifyDraft(platform: PlatformID, result: EgoBridge.Finish, title: String, body: String, imageCount: Int) async throws {
        guard let bridge = bridges[platform] else { throw EgoBridge.BridgeError.toolFailed("没有可校验的渠道页面") }
        try await requiredAdapter(platform).verify(bridge: bridge, result: result, title: title, body: body, imageCount: imageCount)
    }

    public func readReceipt(for platform: PlatformID) async throws -> String {
        guard let bridge = bridges[platform] else {
            throw EgoBridge.BridgeError.toolFailed("没有可读取的草稿会话")
        }
        return try await requiredAdapter(platform).readReceipt(bridge: bridge)
    }
}
