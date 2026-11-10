import Foundation
import Testing
@testable import PublishKit

@MainActor
struct ChannelNavigationTests {
    /// Dedicated local fixture Pages only; never opens or publishes to a social channel.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["INKPOST_NAVIGATION_LIVE"] == "1"))
    func existingPagesCanBeFocusedReopenedAndReportedMissing() async throws {
        let service = DispatchService(registryFactory: {
            ChannelRegistry([NavigationFixtureAdapter(platform: .weibo), NavigationFixtureAdapter(platform: .x)])
        })
        let engine = try EgoLiteEngine()
        let taskID = UUID()
        try await service.beginTask(id: taskID)
        for platform in [PlatformID.weibo, .x] {
            _ = try await service.execute(request: .init(title: "", body: "Local navigation only"),
                execution: .init(taskID: taskID, platform: platform), command: .prepare, onEvent: { _ in })
        }
        let space = try #require(service.workspaceID)
        do {
            try await service.openChannel(.weibo)
            try await service.openChannel(.x)
            let focused = try await engine.runRaw(script: """
            const task = await takeOverTaskSpace(\(space));
            const tabs = await task.tabs();
            const active = tabs.find(tab => tab.active);
            await task.page("p1").close();
            await task.handOff();
            cliLog(JSON.stringify({count:tabs.length, active:active?.label}));
            """)
            #expect(focused.json?["count"] as? Int == 2)
            #expect(focused.string("active") == "p2")
            await #expect(throws: ChannelNavigationError.pageUnavailable) { try await service.openChannel(.weibo) }
            try await service.completeTask()
            let completed = try await engine.runRaw(script: """
            const info = (await listTaskSpaces()).find(space => space.id === \(space));
            cliLog(JSON.stringify({ownership:info?.ownership}));
            """)
            #expect(completed.string("ownership") == "user")
            try await service.openChannel(.x)
            try await service.openWorkspace(id: space)
        } catch {
            _ = try? await engine.runRaw(script: "const info = (await listTaskSpaces()).find(s => s.id === \(space)); const task = await (info?.ownership === 'user' ? claimTaskSpace : takeOverTaskSpace)(\(space)); for (const tab of await task.tabs()) { if (!tab.label) await task.adopt(tab.page); } await task.finish({keep:[]}); cliLog(JSON.stringify({ok:true}));")
            throw error
        }
        _ = try await engine.runRaw(script: "const info = (await listTaskSpaces()).find(s => s.id === \(space)); const task = await (info?.ownership === 'user' ? claimTaskSpace : takeOverTaskSpace)(\(space)); for (const tab of await task.tabs()) { if (!tab.label) await task.adopt(tab.page); } await task.finish({keep:[]}); cliLog(JSON.stringify({ok:true}));")
    }
}

private final class NavigationFixtureAdapter: ChannelAdapter {
    let platform: PlatformID
    let capabilities = ChannelCapabilities(usesTitle: false, maximumImages: 0, isArticle: false)
    init(platform: PlatformID) { self.platform = platform }
    @MainActor func execute(request: ChannelRequest, context: ChannelExecutionContext) async throws -> ChannelOutcome {
        _ = try await context.bridge.navigate(url: Resources.url("fixture-page", ext: "html", sub: "Fixtures").absoluteString + "?channel=\(platform.rawValue)")
        return .failed(.init(code: .verificationFailed, stage: .verifyingContent,
                             detail: "Local navigation fixture", recovery: .inspectionRequired))
    }
}
