import Foundation

public struct ChannelCapabilities {
    public let usesTitle: Bool
    public let isArticle: Bool
    public let requiresLLM: Bool
    public let entryURL: String?
    public let maximumImages: Int
    public init(usesTitle: Bool, requiresLLM: Bool, maximumImages: Int, entryURL: String? = nil, isArticle: Bool = false) {
        self.isArticle = isArticle
        self.usesTitle = usesTitle; self.requiresLLM = requiresLLM; self.maximumImages = maximumImages; self.entryURL = entryURL
    }
}

public struct ChannelRequest: Equatable, Sendable {
    public let title: String
    public let body: String
    public let html: String
    public let tags: [String]
    public let assets: [String]
    public init(title: String, body: String, html: String = "", tags: [String] = [], assets: [String] = []) {
        self.title = title; self.body = body; self.html = html; self.tags = tags; self.assets = assets
    }
    public var tagText: String { tags.map { "#" + $0.trimmingCharacters(in: CharacterSet(charactersIn: "#")) }.joined(separator: " ") }
    public var taggedBody: String { body + (tags.isEmpty ? "" : "\n\n" + tagText) }
}

public protocol ChannelAdapter: AnyObject {
    var platform: PlatformID { get }
    var capabilities: ChannelCapabilities { get }
    @MainActor func execute(request: ChannelRequest, context: ChannelExecutionContext) async throws -> ChannelOutcome
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

/// Internal implementation detail for channels that use an LLM.
class AgentChannelAdapter: ChannelAdapter {
    var platform: PlatformID { preconditionFailure("Override platform") }
    var capabilities: ChannelCapabilities { preconditionFailure("Override capabilities") }
    let makeLLM: (LLMConfig) -> any LLMSession
    init(makeLLM: @escaping (LLMConfig) -> any LLMSession = { OpenAICompatClient(config: $0) }) { self.makeLLM = makeLLM }
    func goal(for request: ChannelRequest) -> String { preconditionFailure("Override platform instructions") }
    func expectedBody(for request: ChannelRequest) -> String { request.taggedBody }
    @MainActor
    func verify(request: ChannelRequest, bridge: EgoBridge, result: EgoBridge.Finish) async throws {
        try await DraftVerifier.verify(bridge: bridge, result: result, request: request, expectedBody: expectedBody(for: request), usesTitle: capabilities.usesTitle)
    }
    @MainActor
    func execute(request: ChannelRequest, context: ChannelExecutionContext) async throws -> ChannelOutcome {
        try context.advance(.openingEditor)
        let result = try await AgentExecutor.run(llm: makeLLM(context.config), bridge: context.bridge,
            goal: goal(for: request) + "\n恢复时先检查现有内容，不重复插入；只通过 finish 结束。",
            onEvent: { [weak context] message in Task { @MainActor in context?.diagnostic(message) } },
            onStage: { stage in try await context.advance(stage) })
        try Task.checkCancellation()
        switch result.status {
        case "needLogin":
            try context.advance(.checkingLogin)
            return .waitingForUser(.init(code: .loginRequired, stage: .checkingLogin, detail: result.message, recovery: .loginRequired))
        case "draftReady":
            try context.advance(.verifyingContent)
            try await verify(request: request, bridge: context.bridge, result: result)
            return .readyForReview(message: result.message)
        case "failed":
            return .failed(.init(code: .executionFailed, stage: context.stage, detail: result.message, recovery: .inspectionRequired))
        default:
            return .failed(.init(code: .executionFailed, stage: context.stage, detail: "模型返回未知结果", recovery: .inspectionRequired))
        }
    }
}
