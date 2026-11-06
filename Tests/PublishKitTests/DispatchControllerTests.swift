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
        #expect(service.requests[0].body == "Test body")
        #expect(service.requests[0].tags == ["swift", "macOS"])
        #expect(service.requests[1] == service.requests[0])
        #expect(service.requests[2] == service.requests[0])
    }

    @Test func testRetryOnlyResumesFailedChannelAndKeepsSnapshot() async throws {
        let service = FakeDispatchService()
        service.statuses[.x] = "needLogin"
        let controller = makeController(service)
        controller.dispatch()
        try await waitForDispatch(controller)
        #expect(controller.state.overallPhase == .failed)
        let original = service.requests.last
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
        #expect(service.requests.last == original)
        #expect(service.bodies.last == originalBody)
        #expect(service.tagSnapshots.last == originalTags)
        #expect(service.assetSnapshots.last == originalAssets)
        #expect(controller.state.overallPhase == .awaitingConfirm)
    }

    @Test func testZhihuOptionalTitleDoesNotRequireLLMKey() {
        let controller = makeController(FakeDispatchService())
        controller.state.selectedPlatforms = [.zhihu]
        controller.state.apiKey = ""
        controller.state.title = ""
        #expect(controller.canDispatch)
        controller.state.title = "想法标题"
        #expect(controller.canDispatch)
        controller.state.selectedPlatforms = [.zhihu, .x]
        #expect(!controller.canDispatch)
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
        #expect(ZhihuChannelAdapter().capabilities.usesTitle == true)
    }

    @Test func testFullBodyAndHTMLReachAdapter() {
        let body = String(repeating: "完整内容", count: 400)
        let request = ChannelRequest(title: "Title", body: body, html: "<p>rich</p>", tags: ["swift"])
        let goal = FixtureChannelAdapter().goal(for: request)
        #expect(goal.contains(body))
        #expect(goal.contains("<p>rich</p>"))
        #expect(goal.contains("#swift"))
        #expect(XChannelAdapter().goal(for: request).contains("#swift"))
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

    @Test func testResetClearsContractState() async throws {
        let controller = makeController(FakeDispatchService())
        controller.dispatch(); try await waitForDispatch(controller)
        #expect(!controller.state.platformOutcomes.isEmpty)
        controller.reset()
        #expect(controller.state.platformOutcomes.isEmpty)
        #expect(controller.state.platformEvents.isEmpty)
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

    @Test func testCancellationStopsLaterChannelsAndPreservesDraft() async throws {
        let service = FakeDispatchService(); service.pause = true
        let controller = makeController(service)
        controller.dispatch()
        while service.platforms.isEmpty { try await Task.sleep(for: .milliseconds(1)) }
        controller.cancel(); try await waitForDispatch(controller)
        #expect(controller.state.overallPhase == .cancelled)
        #expect(service.platforms == [.zhihu])
        #expect(controller.state.platformPhase[.x] == .cancelled)
        #expect(controller.state.markdown == "Test **body**")
        controller.editUnfinishedChannels()
        #expect(controller.state.overallPhase == .pending)
    }

    @Test func testOldTaskAndWrongAttemptEventsAreIgnored() async throws {
        let service = FakeDispatchService()
        let controller = makeController(service)
        controller.dispatch(); try await waitForDispatch(controller)
        let previous = try #require(service.callbacks.first)
        let oldID = try #require(service.executions.first)
        controller.reset(); service.pause = true
        controller.dispatch()
        while service.platforms.count == 3 { try await Task.sleep(for: .milliseconds(1)) }
        let callback = try #require(service.callbacks.last)
        let current = try #require(service.executions.last)
        previous(.init(execution: oldID, payload: .diagnostic("old task")))
        callback(.init(execution: .init(taskID: current.taskID, platform: current.platform), payload: .diagnostic("wrong attempt")))
        #expect(!controller.state.eventLog.contains { $0.contains("old task") || $0.contains("wrong attempt") })
        callback(.init(execution: current, payload: .stage(.uploadingAssets)))
        #expect(controller.state.platformEvents[current.platform]?.payload == .stage(.uploadingAssets))
        controller.cancel(); try await waitForDispatch(controller)
        callback(.init(execution: current, payload: .diagnostic("after finish")))
        #expect(!controller.state.eventLog.contains { $0.contains("after finish") })
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
    var pause = false
    var callbacks: [@MainActor @Sendable (ChannelEvent) -> Void] = []
    var executions: [ChannelExecutionID] = []
    var requests: [ChannelRequest] = []
    var bodies: [String] = []
    var tagSnapshots: [[String]] = []
    var assetSnapshots: [[String]] = []
    func beginTask(id: UUID) async throws {}
    func resumeControl() async throws {}
    func capabilities(for platform: PlatformID) -> ChannelCapabilities? { ChannelRegistry.standard.adapter(for: platform)?.capabilities }
    func execute(request: ChannelRequest, execution: ChannelExecutionID, command: ChannelCommand, config: LLMConfig,
                 onEvent: @escaping @MainActor @Sendable (ChannelEvent) -> Void) async throws -> ChannelOutcome {
        let platform = execution.platform
        platforms.append(platform); requests.append(request)
        callbacks.append(onEvent); executions.append(execution)
        if pause { try await Task.sleep(for: .seconds(10)) }
        bodies.append(request.body); tagSnapshots.append(request.tags); assetSnapshots.append(request.assets)
        if platform == throwPlatform { throw NSError(domain: "test", code: 1) }
        if platform == verificationFailure {
            return .failed(.init(code: .verificationFailed, stage: .verifyingContent, detail: "verification failed", recovery: .inspectionRequired))
        }
        switch statuses[platform] ?? "draftReady" {
        case "draftReady": return .readyForReview(message: "test")
        case "needLogin": return .waitingForUser(.init(code: .loginRequired, stage: .checkingLogin, detail: "login", recovery: .loginRequired))
        default: return .failed(.init(code: .executionFailed, stage: .openingEditor, detail: "failed", recovery: .retryAllowed))
        }
    }
}
