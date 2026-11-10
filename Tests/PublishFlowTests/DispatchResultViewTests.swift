import AppKit
import SwiftUI
import Testing
import PublishKit
@testable import PublishFlow

@MainActor
struct DispatchResultViewTests {
    @Test func fourStatusIconsHaveDistinctAccessibleMeaning() {
        #expect(ChannelStatusPresentation(phase: .preparing) == .filling)
        #expect(ChannelStatusPresentation(phase: .awaitingConfirm) == .ready)
        #expect(ChannelStatusPresentation(phase: .needLogin) == .login)
        #expect(ChannelStatusPresentation(phase: .failed) == .problem)
        #expect(ChannelStatusPresentation(phase: .cancelled) == .problem)
        #expect(Set(ChannelStatusPresentation.allCases.map(\.symbol)).count == 4)
        #expect(ChannelStatusPresentation.login.canOpen)
        #expect(!ChannelStatusPresentation.ready.canOpen)
    }

    @Test func nativeResultLayoutStaysCompactAcrossTerminalStates() throws {
        _ = NSApplication.shared
        let model = DispatchModel()
        let controller = DispatchController(service: ResultViewService(), settings: DispatchSettings(), state: model)
        model.markdown = "写一份内容，填写到多个渠道。\n\n最后由自己确认发布。"
        model.taskPlatforms = [.zhihu, .jike, .x, .weibo, .juejin]
        model.selectedPlatforms = model.taskPlatforms
        for phase in [TargetPhase.failed, .awaitingConfirm, .cancelled, .needLogin, .preparing] {
            model.overallPhase = phase
            model.platformPhase = Dictionary(uniqueKeysWithValues: model.taskPlatforms.map { ($0, TargetPhase.awaitingConfirm) })
            if phase == .failed { model.platformPhase[.weibo] = .failed }
            if phase == .needLogin { model.platformPhase[.weibo] = .needLogin; model.platformPhase[.jike] = .needLogin }
            if phase == .preparing { model.platformPhase[.x] = .preparing; model.platformPhase[.weibo] = .needLogin }
            model.navigationMessage = phase == .awaitingConfirm ? "未能打开工作区，内容已保留，请重试。" : nil
            model.canIgnoreWorkspaceError = phase == .awaitingConfirm
            // Technical diagnostics must not expand the native result area.
            model.eventLog = Array(repeating: "page.click timed out after 30003ms", count: 100)
            model.platformMessages[.weibo] = String(repeating: "raw failure ", count: 200)
            let hosting = NSHostingView(rootView: CompactView(model: model, controller: controller, presentation: TaskPresentation()))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = hosting
            let size = hosting.fittingSize
            #expect(abs(size.width - 420) < 1)
            #expect(size.height < 600)
            hosting.setFrameSize(size)
            hosting.layoutSubtreeIfNeeded()
            if ProcessInfo.processInfo.environment["INKPOST_UI_SNAPSHOTS"] == "1" {
                let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                let data = try #require(bitmap.representation(using: .png, properties: [:]))
                try data.write(to: URL(fileURLWithPath: "/tmp/inkpost-48-native-\(phase.rawValue).png"))
            }
            window.orderOut(nil)
        }
    }
}

@MainActor
private final class ResultViewService: DispatchServicing {
    var workspaceID: Int? { nil }
    func beginTask(id: UUID) async throws {}
    func handOff() async throws {}
    func resumeControl() async throws {}
    func capabilities(for platform: PlatformID) -> ChannelCapabilities? { ChannelRegistry.standard.adapter(for: platform)?.capabilities }
    func execute(request: ChannelRequest, execution: ChannelExecutionID, command: ChannelCommand,
                 onEvent: @escaping @MainActor @Sendable (ChannelEvent) -> Void) async throws -> ChannelOutcome {
        .readyForReview(message: "fixture")
    }
}
