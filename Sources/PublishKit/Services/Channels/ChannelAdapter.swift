import Foundation

public struct ChannelCapabilities {
    public let usesTitle: Bool
    public let requiresTitle: Bool
    public let maximumTitleCharacters: Int?
    public let maximumBodyCharacters: Int?
    public let isArticle: Bool
    public let entryURL: String?
    public let maximumImages: Int
    public init(usesTitle: Bool, maximumImages: Int, entryURL: String? = nil, isArticle: Bool = false, requiresTitle: Bool = false, maximumTitleCharacters: Int? = nil, maximumBodyCharacters: Int? = nil) {
        self.requiresTitle = requiresTitle
        self.maximumTitleCharacters = maximumTitleCharacters
        self.maximumBodyCharacters = maximumBodyCharacters
        self.isArticle = isArticle
        self.usesTitle = usesTitle; self.maximumImages = maximumImages; self.entryURL = entryURL
    }
}

public struct ChannelRequest: Equatable, Sendable {
    public let title: String
    public let body: String
    public let html: String
    public let assets: [String]
    public init(title: String, body: String, html: String = "", assets: [String] = []) {
        self.title = title; self.body = body; self.html = html; self.assets = assets
    }
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
        .init([ZhihuChannelAdapter(), JikeChannelAdapter(), XChannelAdapter(), WeiboChannelAdapter(), JuejinChannelAdapter(), BilibiliChannelAdapter(), FixtureChannelAdapter()])
    }
}
