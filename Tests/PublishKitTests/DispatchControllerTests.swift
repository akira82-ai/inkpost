import XCTest
@testable import PublishKit

@MainActor
final class DispatchControllerTests: XCTestCase {
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
        XCTAssertNotEqual(controller.state.overallPhase, .preparing, "Dispatch timed out")
    }

    func testSerialDispatchUsesPlatformRulesAndMapsResults() async throws {
        let service = FakeDispatchService()
        service.statuses = [.zhihu: "draftReady", .jike: "needLogin", .x: "failed"]
        let controller = makeController(service)
        controller.state.tagsText = "#swift #macOS"
        controller.dispatch()
        XCTAssertFalse(controller.canDispatch)
        try await waitForDispatch(controller)
        XCTAssertEqual(service.platforms, [.zhihu, .jike, .x])
        XCTAssertEqual(controller.state.platformPhase[.zhihu], .awaitingConfirm)
        XCTAssertEqual(controller.state.platformPhase[.jike], .needLogin)
        XCTAssertEqual(controller.state.platformPhase[.x], .failed)
        XCTAssertTrue(service.goals[0].contains("https://zhuanlan.zhihu.com/write"))
        XCTAssertTrue(service.goals[0].contains("#swift #macOS"))
        XCTAssertTrue(service.goals[1].contains("https://web.okjike.com"))
        XCTAssertTrue(service.goals[2].contains("https://x.com/compose/post"))
    }

    func testServiceFailureDoesNotPreventNextPlatform() async throws {
        let service = FakeDispatchService()
        service.throwPlatform = .zhihu
        let controller = makeController(service)
        controller.dispatch()
        try await waitForDispatch(controller)
        XCTAssertEqual(controller.state.platformPhase[.zhihu], .failed)
        XCTAssertEqual(controller.state.platformPhase[.x], .awaitingConfirm)
        XCTAssertEqual(service.platforms.count, 3)
    }

    func testEmptyContentDoesNotInvokeService() {
        let service = FakeDispatchService()
        let controller = makeController(service)
        controller.state.markdown = ""
        controller.dispatch()
        XCTAssertEqual(controller.state.overallPhase, .pending)
        XCTAssertTrue(service.platforms.isEmpty)
    }

    func testReceiptAndReset() async throws {
        let service = FakeDispatchService()
        let controller = makeController(service)
        controller.readFixtureReceipt(for: .simFixture)
        let deadline = Date().addingTimeInterval(3)
        while controller.state.manualReceipt.isEmpty && Date() < deadline {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertEqual(controller.state.manualReceipt, "https://example.com/post/1")
        controller.reset()
        XCTAssertTrue(controller.state.manualReceipt.isEmpty)
        XCTAssertEqual(controller.state.overallPhase, .pending)
    }

    func testConfigurationUsesExistingKeys() {
        let defaults = UserDefaults(suiteName: "inkpost-tests-\(UUID().uuidString)")!
        let settings = DispatchSettings(defaults: defaults)
        settings.save(apiKey: "key", model: "model")
        XCTAssertEqual(defaults.string(forKey: "deepseek.apiKey"), "key")
        XCTAssertEqual(settings.load().model, "model")
    }
}

@MainActor
private final class FakeDispatchService: DispatchServicing {
    var statuses: [PlatformID: String] = [:]
    var throwPlatform: PlatformID?
    var platforms: [PlatformID] = []
    var goals: [String] = []

    func prepare(platform: PlatformID, goal: String, config: LLMConfig,
                 onEvent: @escaping @Sendable (String) -> Void) async throws -> EgoBridge.Finish {
        platforms.append(platform)
        goals.append(goal)
        if platform == throwPlatform { throw NSError(domain: "test", code: 1) }
        return .init(status: statuses[platform] ?? "draftReady", message: "test")
    }

    func readReceipt(for platform: PlatformID) async throws -> String {
        "https://example.com/post/1"
    }
}
