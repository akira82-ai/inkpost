import Foundation
import Testing
@testable import PublishKit

@MainActor
struct DispatchControllerTests {
    private func makeController(_ service: FakeDispatchService) -> DispatchController {
        let defaults = UserDefaults(suiteName: "inkpost-tests-\(UUID().uuidString)")!
        let controller = DispatchController(service: service, settings: DispatchSettings(defaults: defaults))
        controller.state.apiKey = "test-key"
        controller.state.title = "Test title"
        controller.state.markdown = "Test **body**"
        return controller
    }

    private func waitForDispatch(_ controller: DispatchController) async throws {
        let deadline = Date().addingTimeInterval(3)
        while controller.state.overallPhase == .preparing && Date() < deadline {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        #expect(controller.state.overallPhase != .preparing, "Dispatch timed out")
    }

    @Test func testSerialDispatchUsesPlatformRulesAndMapsResults() async throws {
        let service = FakeDispatchService()
        service.statuses = [.zhihu: "draftReady", .jike: "needLogin", .x: "failed"]
        let controller = makeController(service)
        controller.state.tagsText = "#swift #macOS"
        controller.dispatch()
        #expect(!controller.canDispatch)
        try await waitForDispatch(controller)
        #expect(service.platforms == [.zhihu, .jike, .x])
        #expect(controller.state.platformPhase[.zhihu] == .awaitingConfirm)
        #expect(controller.state.platformPhase[.jike] == .needLogin)
        #expect(controller.state.platformPhase[.x] == .failed)
        #expect(service.goals[0].contains("https://www.zhihu.com/"))
        #expect(service.goals[0].contains("#swift #macOS"))
        #expect(service.goals[1].contains("https://web.okjike.com"))
        #expect(service.goals[2].contains("https://x.com/compose/post"))
    }

    @Test func testRetryOnlyResumesFailedChannelAndKeepsSnapshot() async throws {
        let service = FakeDispatchService()
        service.statuses[.x] = "needLogin"
        let controller = makeController(service)
        controller.dispatch()
        try await waitForDispatch(controller)
        #expect(controller.state.overallPhase == .failed)
        let original = service.goals.last
        let originalBody = service.bodies.last
        let originalTags = service.tagSnapshots.last
        let originalAssets = service.assetSnapshots.last
        controller.state.markdown = "Changed during pause"
        controller.state.tagsText = "#changed"
        controller.state.assetPaths = ["/tmp/changed.png"]
        service.statuses[.x] = "draftReady"
        controller.resume(.x)
        try await waitForDispatch(controller)
        #expect(service.platforms == [.zhihu, .jike, .x, .x])
        #expect(service.goals.last == original)
        #expect(service.bodies.last == originalBody)
        #expect(service.tagSnapshots.last == originalTags)
        #expect(service.assetSnapshots.last == originalAssets)
        #expect(controller.state.overallPhase == .awaitingConfirm)
    }

    @Test func testZhihuDeterministicFlowDoesNotRequireLLMKeyOrTitle() {
        let controller = makeController(FakeDispatchService())
        controller.state.selectedPlatforms = [.zhihu]
        controller.state.apiKey = ""
        controller.state.title = ""
        #expect(controller.canDispatch)
        controller.state.selectedPlatforms = [.zhihu, .x]
        #expect(!controller.canDispatch)
    }

    @Test func testZhihuRejectsUnstructuredAgentEntry() async throws {
        let service = AgentDispatchService()
        do {
            _ = try await service.prepare(platform: .zhihu, goal: "unstructured", config: .init(baseURL: "https://unused.invalid", apiKey: "", model: "unused"), onEvent: { _ in })
            Issue.record("Unstructured Zhihu task unexpectedly accepted")
        } catch {
            #expect(error.localizedDescription.contains("结构化"))
            #expect(service.workspaceID == nil)
        }
    }

    @Test func testZhihuRejectsArticleNavigationBeforeBrowserExecution() async throws {
        let bridge = try EgoBridge(spaceName: "unused", engine: EgoLiteEngine(binaryPath: "/usr/bin/false"))
        for url in ["https://zhuanlan.zhihu.com/write", "https://www.zhihu.com/creator", "https://www.zhihu.com/?redirect=article"] {
            do {
                _ = try await ZhihuChannelAdapter.navigate(bridge: bridge, url: url)
                Issue.record("Unexpected navigation: \(url)")
            } catch {
                #expect(error.localizedDescription.contains("知乎想法仅允许打开首页"))
            }
        }
    }

    @Test func testZhihuUsesThoughtComposerInsteadOfArticle() {
        #expect(PlatformID.zhihu.entryURL == "https://www.zhihu.com/")
        #expect(!PlatformID.zhihu.isArticle)
        #expect(PlatformID.simFixture.isArticle)
        let goal = PlatformRules.goal(for: .zhihu, title: "Title", html: "", plain: "Body", tags: ["测试"], assets: [])
        #expect(goal.contains("知乎想法"))
        #expect(!goal.contains("zhuanlan.zhihu.com"))
        #expect(goal.contains("不把输入标题自动并入正文"))
    }

    @Test func testFullBodyAndHTMLReachPlatformGoal() {
        let body = String(repeating: "完整内容", count: 400)
        let goal = PlatformRules.goal(for: .zhihu, title: "Title", html: "<p>rich</p>", plain: body, tags: [], assets: [])
        #expect(goal.contains(body))
        #expect(goal.contains("<p>rich</p>"))
    }

    @Test func testVerificationFailureIsNotReportedAsFilled() async throws {
        let service = FakeDispatchService()
        service.verificationFailure = .zhihu
        let controller = makeController(service)
        controller.dispatch()
        controller.dispatch()
        try await waitForDispatch(controller)
        #expect(service.platforms.count == 3)
        #expect(controller.state.overallPhase == .failed)
        #expect(controller.state.platformPhase[.zhihu] == .failed)
        #expect(controller.state.platformMessages[.zhihu]?.contains("verification") == true)
    }

    @Test func testEditingUnfinishedChannelsPreservesContentAndExcludesCompleted() async throws {
        let service = FakeDispatchService(); service.statuses[.x] = "failed"
        let controller = makeController(service)
        controller.dispatch(); try await waitForDispatch(controller)
        controller.editUnfinishedChannels()
        #expect(controller.state.overallPhase == .pending)
        #expect(controller.state.selectedPlatforms == [.x])
        #expect(controller.state.markdown == "Test **body**")
    }

    @Test func testSavedChannelSelectionIncludesEmptySelection() {
        let defaults = UserDefaults(suiteName: "inkpost-channels-\(UUID().uuidString)")!
        let settings = DispatchSettings(defaults: defaults)
        settings.savePlatforms([.jike, .x])
        #expect(settings.selectedPlatforms() == [.jike, .x])
        settings.savePlatforms([])
        #expect(settings.selectedPlatforms().isEmpty)
    }

    @Test func testServiceFailureDoesNotPreventNextPlatform() async throws {
        let service = FakeDispatchService()
        service.throwPlatform = .zhihu
        let controller = makeController(service)
        controller.dispatch()
        try await waitForDispatch(controller)
        #expect(controller.state.platformPhase[.zhihu] == .failed)
        #expect(controller.state.platformPhase[.x] == .awaitingConfirm)
        #expect(service.platforms.count == 3)
    }

    @Test func testEmptyContentDoesNotInvokeService() {
        let service = FakeDispatchService()
        let controller = makeController(service)
        controller.state.markdown = ""
        controller.dispatch()
        #expect(controller.state.overallPhase == .pending)
        #expect(service.platforms.isEmpty)
    }

    @Test func testReceiptAndReset() async throws {
        let service = FakeDispatchService()
        let controller = makeController(service)
        controller.readFixtureReceipt(for: .simFixture)
        let deadline = Date().addingTimeInterval(3)
        while controller.state.manualReceipt.isEmpty && Date() < deadline {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        #expect(controller.state.manualReceipt == "https://example.com/post/1")
        controller.reset()
        #expect(controller.state.manualReceipt.isEmpty)
        #expect(controller.state.overallPhase == .pending)
    }

    @Test func testSuccessfulHandoffArchivesAndClearsOnlyCompletedDraft() async throws {
        let service = FakeDispatchService()
        let controller = makeController(service)
        controller.dispatch(); try await waitForDispatch(controller)
        let selection = controller.state.selectedPlatforms
        controller.openWorkspace(); controller.openWorkspace()
        while controller.state.isHandingOff { try await Task.sleep(for: .milliseconds(1)) }
        #expect(service.handoffCount == 1)
        #expect(controller.state.overallPhase == .pending)
        #expect(controller.state.title.isEmpty && controller.state.markdown.isEmpty)
        #expect(controller.state.history.count == 1)
        #expect(controller.state.history.first?.markdown == "Test **body**")
        #expect(controller.state.history.first?.workspaceID == 42)
        #expect(controller.state.selectedPlatforms == selection)
        controller.state.title = "Next"; controller.state.markdown = "Next body"
        controller.dispatch(); try await waitForDispatch(controller)
        #expect(controller.state.history.count == 1)
    }

    @Test func testFailedHandoffAndPartialTaskKeepContent() async throws {
        let service = FakeDispatchService()
        let controller = makeController(service)
        controller.dispatch(); try await waitForDispatch(controller)
        service.handoffFails = true
        controller.openWorkspace()
        while controller.state.isHandingOff { try await Task.sleep(for: .milliseconds(1)) }
        #expect(controller.state.overallPhase == .awaitingConfirm)
        #expect(controller.state.markdown == "Test **body**")
        #expect(controller.state.history.isEmpty)
        controller.state.overallPhase = .failed
        service.handoffFails = false
        controller.openWorkspace()
        while controller.state.isHandingOff { try await Task.sleep(for: .milliseconds(1)) }
        #expect(controller.state.overallPhase == .failed)
        #expect(controller.state.markdown == "Test **body**")
        #expect(controller.state.history.isEmpty)
    }

    @Test func testConfigurationUsesExistingKeys() {
        let defaults = UserDefaults(suiteName: "inkpost-tests-\(UUID().uuidString)")!
        let settings = DispatchSettings(defaults: defaults)
        settings.save(apiKey: "key", model: "model")
        #expect(defaults.string(forKey: "deepseek.apiKey") == "key")
        #expect(settings.load().model == "model")
    }

    @Test func testImageBatchReportsAddedDuplicatesAndAllOverflow() throws {
        let controller = makeController(FakeDispatchService())
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!
        var paths: [String] = []
        for index in UInt8(0)..<8 {
            let file = root.appendingPathComponent("\(index).png")
            var data = png; data.append(index)
            try data.write(to: file); paths.append(file.path)
        }
        // A duplicate encountered after reaching the limit must remain a duplicate.
        controller.addAssets(paths + [paths[0]])
        #expect(controller.state.assetPaths.count == 6)
        #expect(controller.state.assetData.count == 6)
        #expect(controller.state.notice == "已添加 6 张图片；该图片已经添加；最多 6 张，2 张未添加")
    }

    @Test func testInvalidImageDoesNotDiscardRestOfBatch() throws {
        let controller = makeController(FakeDispatchService())
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let invalid = root.appendingPathComponent("broken.png")
        try Data("invalid image".utf8).write(to: invalid)
        let valid = root.appendingPathComponent("valid.png")
        try Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!.write(to: valid)
        controller.addAssets([invalid.path, valid.path])
        #expect(controller.state.assetPaths.count == 1)
        #expect(controller.state.notice?.contains("已添加 1 张图片") == true)
        #expect(controller.state.notice?.contains("broken.png：无法读取这张图片") == true)
    }
}

@MainActor
private final class FakeDispatchService: DispatchServicing {
    var workspaceID: Int? { 42 }
    var handoffCount = 0
    var handoffFails = false
    func handOff() async throws {
        handoffCount += 1
        if handoffFails { throw NSError(domain: "test-handoff", code: 1) }
    }
    var statuses: [PlatformID: String] = [:]
    var throwPlatform: PlatformID?
    var verificationFailure: PlatformID?
    var platforms: [PlatformID] = []
    var goals: [String] = []
    var bodies: [String] = []
    var tagSnapshots: [[String]] = []
    var assetSnapshots: [[String]] = []
    func prepare(platform: PlatformID, goal: String, body: String, tags: [String], assets: [String], config: LLMConfig,
                 onEvent: @escaping @Sendable (String) -> Void) async throws -> EgoBridge.Finish {
        bodies.append(body); tagSnapshots.append(tags); assetSnapshots.append(assets)
        return try await prepare(platform: platform, goal: goal, config: config, onEvent: onEvent)
    }


    func prepare(platform: PlatformID, goal: String, config: LLMConfig,
                 onEvent: @escaping @Sendable (String) -> Void) async throws -> EgoBridge.Finish {
        platforms.append(platform)
        goals.append(goal)
        if platform == throwPlatform { throw NSError(domain: "test", code: 1) }
        return .init(status: statuses[platform] ?? "draftReady", message: "test")
    }

    func verifyDraft(platform: PlatformID, result: EgoBridge.Finish, title: String, body: String, imageCount: Int) async throws {
        if platform == verificationFailure { throw NSError(domain: "test", code: 2, userInfo: [NSLocalizedDescriptionKey: "verification failed"]) }
    }
    func readReceipt(for platform: PlatformID) async throws -> String {
        "https://example.com/post/1"
    }
}
