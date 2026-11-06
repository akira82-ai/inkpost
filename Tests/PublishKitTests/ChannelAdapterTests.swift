import Foundation
import Testing
@testable import PublishKit

@MainActor
struct ChannelAdapterTests {
    private let config = LLMConfig(baseURL: "https://unused.invalid", apiKey: "", model: "test")

    @Test func registeredAdapterReceivesStructuredContentAndReusesPageOnResume() async throws {
        let adapter = RecordingAdapter()
        var pages = 0
        let service = AgentDispatchService(registryFactory: { .init([adapter]) }, bridgeFactory: { _ in
            pages += 1
            return try EgoBridge(spaceName: "fake", engine: EgoLiteEngine(binaryPath: "/usr/bin/false"))
        })
        try await service.beginTask()
        let request = ChannelRequest(title: "Title", body: "Complete\nbody", html: "<p>Complete</p>", tags: ["swift"], assets: ["/tmp/image.png"])
        let first = try await service.prepare(platform: .weibo, request: request, config: config, onEvent: { _ in })
        #expect(first.status == "needLogin")
        let second = try await service.prepare(platform: .weibo, request: request, config: config, onEvent: { _ in })
        #expect(second.status == "draftReady")
        try await service.verifyDraft(platform: .weibo, result: second, title: request.title, body: request.body, imageCount: 1)
        #expect(pages == 1)
        #expect(adapter.requests.count == 2)
        #expect(adapter.requests.allSatisfy { $0.body == request.body && $0.assets == request.assets && $0.html == request.html && $0.tags == request.tags && $0.title == request.title })
        #expect(adapter.verifications == 1)
        #expect(service.capabilities(for: .weibo)?.requiresLLM == false)
    }

    @Test func adapterFailureDoesNotPreventAnotherChannelAndUnregisteredFailsBeforeBrowser() async throws {
        let failing = RecordingAdapter(platform: .weibo, fail: true)
        let other = RecordingAdapter(platform: .jike)
        var pages = 0
        let service = AgentDispatchService(registryFactory: { .init([failing, other]) }, bridgeFactory: { _ in
            pages += 1
            return try EgoBridge(spaceName: "fake", engine: EgoLiteEngine(binaryPath: "/usr/bin/false"))
        })
        let request = ChannelRequest(title: "", body: "Body")
        do {
            _ = try await service.prepare(platform: .x, request: request, config: config, onEvent: { _ in })
            Issue.record("Unregistered channel accepted")
        } catch { #expect(pages == 0) }
        do {
            _ = try await service.prepare(platform: .weibo, request: request, config: config, onEvent: { _ in })
            Issue.record("Adapter failure swallowed")
        } catch { #expect(error.localizedDescription.contains("adapter failure")) }
        _ = try await service.prepare(platform: .jike, request: request, config: config, onEvent: { _ in })
        #expect(other.requests.count == 1)
        #expect(pages == 2)
    }

    @Test func newTaskCreatesFreshAdapterSession() async throws {
        var created: [RecordingAdapter] = []
        let service = AgentDispatchService(registryFactory: {
            let adapter = RecordingAdapter(); created.append(adapter); return .init([adapter])
        }, bridgeFactory: { _ in try EgoBridge(spaceName: "fake", engine: EgoLiteEngine(binaryPath: "/usr/bin/false")) })
        let request = ChannelRequest(title: "", body: "Body")
        try await service.beginTask()
        _ = try await service.prepare(platform: .weibo, request: request, config: config, onEvent: { _ in })
        try await service.beginTask()
        let result = try await service.prepare(platform: .weibo, request: request, config: config, onEvent: { _ in })
        #expect(created.count == 3)
        #expect(result.status == "needLogin")
        #expect(created[1].requests.count == 1)
        #expect(created[2].requests.count == 1)
    }

    @Test func capabilityLimitIsCheckedBeforeBrowserWork() async throws {
        let service = AgentDispatchService(registryFactory: { .init([RecordingAdapter()]) }, bridgeFactory: { _ in
            Issue.record("Browser invoked for invalid input")
            return try EgoBridge(spaceName: "fake", engine: EgoLiteEngine(binaryPath: "/usr/bin/false"))
        })
        do {
            _ = try await service.prepare(platform: .weibo, request: .init(title: "", body: "Body", assets: ["a", "b"]), config: config, onEvent: { _ in })
            Issue.record("Image limit ignored")
        } catch { #expect(error.localizedDescription.contains("图片超过")) }
    }
}

private final class RecordingAdapter: ChannelAdapter {
    let platform: PlatformID
    let capabilities = ChannelCapabilities(usesTitle: false, requiresLLM: false, maximumImages: 1)
    var requests: [ChannelRequest] = []
    var verifications = 0
    let fail: Bool
    init(platform: PlatformID = .weibo, fail: Bool = false) { self.platform = platform; self.fail = fail }
    func goal(for request: ChannelRequest) -> String { request.body }
    @MainActor func prepare(request: ChannelRequest, bridge: EgoBridge, config: LLMConfig,
                            onEvent: @escaping @Sendable (String) -> Void) async throws -> EgoBridge.Finish {
        requests.append(request)
        if fail { throw EgoBridge.BridgeError.toolFailed("adapter failure") }
        return .init(status: requests.count == 1 ? "needLogin" : "draftReady", message: "test")
    }
    @MainActor func verify(bridge: EgoBridge, result: EgoBridge.Finish, title: String, body: String, imageCount: Int) async throws {
        verifications += 1
    }
}
