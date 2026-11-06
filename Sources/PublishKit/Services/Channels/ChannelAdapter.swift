import Foundation

public struct ChannelCapabilities {
    public let usesTitle: Bool
    public let requiresLLM: Bool
    public let entryURL: String?
    public let maximumImages: Int
    public init(usesTitle: Bool, requiresLLM: Bool, maximumImages: Int, entryURL: String? = nil) {
        self.usesTitle = usesTitle; self.requiresLLM = requiresLLM; self.maximumImages = maximumImages; self.entryURL = entryURL
    }
}

public struct ChannelRequest {
    public let title: String
    public let body: String
    public let html: String
    public let tags: [String]
    public let assets: [String]
    // Used only by historical CLI/service callers. Production dispatch uses structured fields.
    let legacyGoal: String?
    public init(title: String, body: String, html: String = "", tags: [String] = [], assets: [String] = [], legacyGoal: String? = nil) {
        self.title = title; self.body = body; self.html = html; self.tags = tags; self.assets = assets; self.legacyGoal = legacyGoal
    }
}

public protocol ChannelAdapter: AnyObject {
    var platform: PlatformID { get }
    var capabilities: ChannelCapabilities { get }
    func goal(for request: ChannelRequest) -> String
    @MainActor func prepare(request: ChannelRequest, bridge: EgoBridge, config: LLMConfig,
                            onEvent: @escaping @Sendable (String) -> Void) async throws -> EgoBridge.Finish
    @MainActor func readReceipt(bridge: EgoBridge) async throws -> String
    @MainActor func verify(bridge: EgoBridge, result: EgoBridge.Finish, title: String, body: String, imageCount: Int) async throws
}

public extension ChannelAdapter {
    @MainActor func readReceipt(bridge: EgoBridge) async throws -> String {
        throw EgoBridge.BridgeError.toolFailed("此渠道不支持读取回执")
    }
}

/// A registry is scoped to a task: adapter instances retain only that task's recovery state.
public struct ChannelRegistry {
    private let adapters: [PlatformID: any ChannelAdapter]
    public init(_ adapters: [any ChannelAdapter]) {
        precondition(Set(adapters.map(\.platform)).count == adapters.count, "Duplicate channel adapter")
        self.adapters = Dictionary(uniqueKeysWithValues: adapters.map { ($0.platform, $0) })
    }
    public func adapter(for platform: PlatformID) -> (any ChannelAdapter)? { adapters[platform] }
    public static var standard: ChannelRegistry {
        .init([ZhihuChannelAdapter(), JikeChannelAdapter(), XChannelAdapter(), FixtureChannelAdapter()])
    }
}

class AgentChannelAdapter: ChannelAdapter {
    var platform: PlatformID { preconditionFailure("Override platform") }
    var capabilities: ChannelCapabilities { preconditionFailure("Override capabilities") }
    func goal(for request: ChannelRequest) -> String { preconditionFailure("Override platform instructions") }
    @MainActor
    func prepare(request: ChannelRequest, bridge: EgoBridge, config: LLMConfig,
                 onEvent: @escaping @Sendable (String) -> Void) async throws -> EgoBridge.Finish {
        onEvent("调用 \(config.model) @ \(config.baseURL)")
        return try await AgentDispatchService.run(llm: OpenAICompatClient(config: config), bridge: bridge,
            goal: (request.legacyGoal ?? goal(for: request)) + "\n\n恢复要求：先检查现有页面与内容，已填写的标题、正文和图片不要重复插入；需要时修改原字段。", onEvent: onEvent)
    }
    @MainActor
    func readReceipt(bridge: EgoBridge) async throws -> String {
        throw EgoBridge.BridgeError.toolFailed("此渠道不支持读取回执")
    }
    @MainActor
    func verify(bridge: EgoBridge, result: EgoBridge.Finish, title: String, body: String, imageCount: Int) async throws {
        try await DraftVerifier.verify(bridge: bridge, result: result, title: title, body: body, imageCount: imageCount, usesTitle: capabilities.usesTitle)
    }
}
