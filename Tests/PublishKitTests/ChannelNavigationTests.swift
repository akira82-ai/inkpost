import Foundation
import Testing
@testable import PublishKit

@MainActor
struct ChannelNavigationTests {
    /// Opens only unique local fixtures in the current Space, preserving every original tab.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["INKPOST_NAVIGATION_LIVE"] == "1"))
    func currentSpaceRetainsOriginalTabsAndAddsOnlyChannelTabs() async throws {
        let marker = UUID().uuidString
        let service = DispatchService(registryFactory: {
            ChannelRegistry([NavigationFixtureAdapter(platform: .weibo, marker: marker), NavigationFixtureAdapter(platform: .x, marker: marker)])
        })
        let engine = try EgoLiteEngine()
        let before = try await engine.runRaw(script: "cliLog(JSON.stringify({ids:(await listTaskSpaces()).map(s=>s.id)}));")
        let taskID = UUID()
        try await service.beginTask(id: taskID)
        let space = try #require(service.workspaceID)
        let original = try await engine.runRaw(script: "const task=await taskSpace(\(space)); cliLog(JSON.stringify({targets:(await task.tabs()).map(t=>t.targetId)}));")
        let targets = try #require(original.json?["targets"] as? [String])
        do {
            for platform in [PlatformID.weibo, .x] {
                _ = try await service.execute(request: .init(title: "", body: "Local navigation only"),
                    execution: .init(taskID: taskID, platform: platform), command: .prepare, onEvent: { _ in })
            }
            try await service.openChannel(.weibo)
            try await service.openChannel(.x)
            try await service.completeTask()
            try await service.openWorkspace(id: space)
            let result = try await engine.runRaw(script: """
            const spaces=await listTaskSpaces();
            const task=await claimTaskSpace(\(space));
            const tabs=await task.tabs();
            await task.finish({keep:"all"});
            cliLog(JSON.stringify({ids:spaces.map(s=>s.id), ownership:spaces.find(s=>s.id===\(space))?.ownership,
                targets:tabs.map(t=>t.targetId), fixtures:tabs.filter(t=>t.url.includes("\(marker)")).length}));
            """)
            #expect(result.json?["ids"] as? [Int] == before.json?["ids"] as? [Int])
            #expect(result.string("ownership") == "user")
            #expect(result.json?["fixtures"] as? Int == 2)
            let afterTargets = try #require(result.json?["targets"] as? [String])
            #expect(Set(targets).isSubset(of: Set(afterTargets)))
            #expect(afterTargets.count == targets.count + 2)
            await #expect(throws: ChannelNavigationError.pageUnavailable) { try await service.openChannel(.zhihu) }
        } catch {
            try await cleanup(engine: engine, space: space, marker: marker)
            throw error
        }
        try await cleanup(engine: engine, space: space, marker: marker)
    }

    private func cleanup(engine: EgoLiteEngine, space: Int, marker: String) async throws {
        _ = try await engine.runRaw(script: """
        const info=(await listTaskSpaces()).find(s=>s.id===\(space));
        const task=await (info?.ownership === "user" ? claimTaskSpace : takeOverTaskSpace)(\(space));
        try {
            for (const tab of await task.tabs()) {
                if (tab.url.includes("\(marker)")) {
                    const page=tab.label ? task.page(tab.label) : await task.adopt(tab.page);
                    await page.close();
                }
            }
        } finally { await task.finish({keep:"all"}); }
        cliLog(JSON.stringify({ok:true}));
        """)
    }
}

private final class NavigationFixtureAdapter: ChannelAdapter {
    let platform: PlatformID
    let marker: String
    let capabilities = ChannelCapabilities(usesTitle: false, maximumImages: 0, isArticle: false)
    init(platform: PlatformID, marker: String) { self.platform = platform; self.marker = marker }
    @MainActor func execute(request: ChannelRequest, context: ChannelExecutionContext) async throws -> ChannelOutcome {
        _ = try await context.bridge.navigate(url: Resources.url("fixture-page", ext: "html", sub: "Fixtures").absoluteString + "?inkpost52=\(marker)&channel=\(platform.rawValue)")
        return .failed(.init(code: .verificationFailed, stage: .verifyingContent,
                             detail: "Local navigation fixture", recovery: .inspectionRequired))
    }
}
