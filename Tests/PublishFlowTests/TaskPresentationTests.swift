import AppKit
import SwiftUI
import Foundation
import Testing
import PublishKit
@testable import PublishFlow

@MainActor
struct TaskPresentationTests {
    @Test func hideOnlyAfterExecutionStartsAndOnlyOncePerTask() {
        let model = DispatchModel()
        let presentation = TaskPresentation()
        model.taskID = UUID()
        #expect(!presentation.claimHide(for: model))
        model.overallPhase = .preparing
        #expect(!presentation.claimHide(for: model))
        model.currentPlatform = .zhihu
        presentation.compactVisible = true
        #expect(presentation.claimHide(for: model))
        presentation.compactVisible = false
        model.currentPlatform = .x
        #expect(!presentation.claimHide(for: model))
        model.overallPhase = .failed
        model.overallPhase = .preparing
        #expect(!presentation.claimHide(for: model))
        model.taskID = UUID()
        #expect(presentation.claimHide(for: model))
    }

    @Test func workspaceHidesOnceAndManualRestoreStaysVisible() async throws {
        _ = NSApplication.shared
        let model = DispatchModel()
        let presentation = TaskPresentation()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 180),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = NSHostingView(rootView: Text("Local presentation test")
            .modifier(TaskWindowPresentation(model: model, presentation: presentation, dismiss: { window.orderOut(nil) })))
        window.orderFront(nil)
        try await Task.sleep(for: .milliseconds(100))
        model.taskID = UUID()
        model.overallPhase = .preparing
        model.currentPlatform = .zhihu
        try await Task.sleep(for: .milliseconds(100))
        #expect(!window.isVisible)
        window.orderFront(nil)
        model.currentPlatform = .x
        try await Task.sleep(for: .milliseconds(100))
        #expect(window.isVisible)
    }

    @Test func menuStatusUsesRealChannelResults() {
        let model = DispatchModel()
        let status = MenuBarStatus(model: model)
        #expect(status.message.isEmpty)
        #expect(status.title == "墨")
        model.overallPhase = .preparing
        model.taskPlatforms = [.zhihu, .x]
        model.currentPlatform = .x
        model.platformPhase[.zhihu] = .awaitingConfirm
        #expect(status.message == "正在填写：X")
        #expect(status.isRunning)
        #expect(!status.needsAttention)
        model.overallPhase = .failed
        #expect(status.message == "需要处理：X")
        #expect(!status.isRunning)
        #expect(status.needsAttention)
        model.taskPlatforms = [.zhihu, .jike, .x]
        model.platformPhase[.jike] = .needLogin
        model.platformPhase[.x] = .failed
        #expect(status.message == "需要处理：即刻、X")
        #expect(status.needsAttention)
        #expect(!status.isRunning)
        model.platformPhase[.zhihu] = .failed
        #expect(status.message == "需要处理：知乎、即刻、X")
        model.overallPhase = .awaitingConfirm
        #expect(status.message == "已填好，请确认")
        #expect(!status.isRunning)
        #expect(!status.needsAttention)
        model.overallPhase = .cancelled
        #expect(status.message == "已停止")
        #expect(!status.isRunning)
        #expect(!status.needsAttention)
        model.overallPhase = .pending
        #expect(status.title == "墨")
        #expect(!status.needsAttention)
    }
}
