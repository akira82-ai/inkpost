import AppKit
import SwiftUI
import Testing
import PublishKit
@testable import PublishFlow

@MainActor
struct NativeMenuBarTests {
    private func makeMenuBar(controller: DispatchController, presentation: TaskPresentation,
                             openSettings: @escaping () -> Void, window: NSWindow? = nil) -> NativeMenuBar {
        let mainWindow = window ?? NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 540),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        if window == nil {
            mainWindow.contentViewController = NSHostingController(rootView:
                CompactView(model: controller.state, controller: controller, presentation: presentation))
        }
        return NativeMenuBar(controller: controller, presentation: presentation, openSettings: openSettings, window: mainWindow)
    }

    @Test func launchUsesAccessoryPolicyWithoutDockPresence() {
        _ = NSApplication.shared
        let previousPolicy = NSApp.activationPolicy()
        defer { NSApp.setActivationPolicy(previousPolicy) }
        let lifecycle = AppLifecycle()
        lifecycle.applicationWillFinishLaunching(Notification(name: NSApplication.willFinishLaunchingNotification))
        #expect(NSApp.activationPolicy() == .accessory)
        #expect(!lifecycle.applicationShouldTerminateAfterLastWindowClosed(NSApp))
    }

    @Test func nativeFramesAdvanceWithoutChangingCopyOrWidthAndStopAtCompletion() async throws {
        _ = NSApplication.shared
        let controller = DispatchController(service: DispatchService(), settings: DispatchSettings())
        let bar = makeMenuBar(controller: controller, presentation: TaskPresentation(), openSettings: {})
        defer { bar.stop() }
        #expect(bar.item.length == NSStatusItem.squareLength)
        #expect(bar.item.button?.imagePosition == .imageOnly)
        let model = controller.state
        model.taskPlatforms = [.zhihu, .x]
        model.currentPlatform = .zhihu
        model.overallPhase = .preparing
        try await Task.sleep(for: .milliseconds(120))
        let title = bar.item.button?.title
        let width = bar.item.length
        let first = bar.item.button?.image?.tiffRepresentation
        let count = bar.frameUpdates
        try await Task.sleep(for: .milliseconds(400))
        #expect(title == " 正在填写：知乎")
        #expect(bar.item.button?.title == title)
        #expect(bar.item.length == width)
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            #expect(!bar.isAnimating)
            #expect(bar.frameUpdates == count)
        } else {
            #expect(bar.isAnimating)
            #expect(bar.frameUpdates > count)
            #expect(bar.item.button?.image?.tiffRepresentation != first)
        }
        model.currentPlatform = .x
        try await Task.sleep(for: .milliseconds(100))
        #expect(bar.item.button?.title == " 正在填写：X")
        model.overallPhase = .awaitingConfirm
        try await Task.sleep(for: .milliseconds(100))
        #expect(!bar.isAnimating)
        #expect(bar.item.button?.title == " 已填好，请确认")
        let stoppedCount = bar.frameUpdates
        try await Task.sleep(for: .milliseconds(150))
        #expect(bar.frameUpdates == stoppedCount)
        model.platformPhase[.zhihu] = .awaitingConfirm
        model.platformPhase[.x] = .needLogin
        model.overallPhase = .failed
        try await Task.sleep(for: .milliseconds(100))
        #expect(!bar.isAnimating)
        #expect(bar.item.button?.title == " 需要处理：X")
        model.overallPhase = .cancelled
        try await Task.sleep(for: .milliseconds(100))
        #expect(!bar.isAnimating)
        #expect(bar.item.button?.title == " 已停止")
        model.overallPhase = .pending
        try await Task.sleep(for: .milliseconds(100))
        #expect(bar.item.length == NSStatusItem.squareLength)
        #expect(bar.item.button?.imagePosition == .imageOnly)
    }

    @Test func mainWindowStaysOpenAcrossProgressAndAllTerminalStates() async throws {
        _ = NSApplication.shared
        let controller = DispatchController(service: DispatchService(), settings: DispatchSettings())
        let model = controller.state
        let presentation = TaskPresentation()
        let bar = makeMenuBar(controller: controller, presentation: presentation, openSettings: {})
        let other = NSWindow(contentRect: NSRect(x: 20, y: 20, width: 200, height: 120),
                             styleMask: [.titled], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        defer { bar.stop(); other.close() }
        #expect(type(of: bar.mainWindow) == NSWindow.self)
        #expect(bar.mainWindow.level == .normal)
        #expect(!bar.mainWindow.hidesOnDeactivate)
        bar.item.button?.performClick(nil)
        try await Task.sleep(for: .milliseconds(350))
        #expect(bar.mainWindow.isVisible)
        // Invalid input never starts a task or hides the UI.
        model.markdown = ""
        controller.dispatch()
        #expect(model.overallPhase == .pending)
        #expect(bar.mainWindow.isVisible)
        // Accepted start hides once.
        model.taskID = UUID()
        model.overallPhase = .preparing
        model.currentPlatform = .zhihu
        let hiddenDeadline = Date().addingTimeInterval(1)
        while bar.mainWindow.isVisible && Date() < hiddenDeadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!bar.mainWindow.isVisible)
        // User restores the main window while work continues.
        bar.item.button?.performClick(nil)
        try await Task.sleep(for: .milliseconds(350))
        #expect(bar.mainWindow.isVisible)
        model.currentPlatform = .x
        other.makeKeyAndOrderFront(nil)
        for phase in [TargetPhase.awaitingConfirm, .failed, .cancelled, .needLogin] {
            model.overallPhase = phase
            model.currentPlatform = nil
            try await Task.sleep(for: .milliseconds(50))
            #expect(bar.mainWindow.isVisible)
        }
        // Repeated menu clicks always wake the window, including while another app covers it.
        let focus = presentation.bodyFocusRequest
        bar.item.button?.performClick(nil)
        #expect(bar.mainWindow.isVisible)
        #expect(presentation.bodyFocusRequest != focus)
    }

    @Test func mainWindowIsOrdinaryAndCanBeCovered() async throws {
        _ = NSApplication.shared
        let previousPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.accessory)
        defer { NSApp.setActivationPolicy(previousPolicy) }
        let controller = DispatchController(service: DispatchService(), settings: DispatchSettings())
        let presentation = TaskPresentation()
        let workspace = NSWindow(contentRect: NSRect(x: 20, y: 20, width: 500, height: 500),
                                 styleMask: [.titled], backing: .buffered, defer: false)
        workspace.isReleasedWhenClosed = false
        var settingsOpens = 0
        let bar = makeMenuBar(controller: controller, presentation: presentation, openSettings: { settingsOpens += 1 })
        let other = NSWindow(contentRect: bar.mainWindow.frame, styleMask: [.titled], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        defer { bar.stop(); workspace.close(); other.close() }
        workspace.orderFront(nil)
        bar.item.button?.performClick(nil)
        try await Task.sleep(for: .milliseconds(100))
        #expect(type(of: bar.mainWindow) == NSWindow.self)
        #expect(!(bar.mainWindow is NSPanel))
        #expect(bar.mainWindow.level == .normal)
        #expect(bar.mainWindow.canBecomeKey)
        // The CLI test runner can lose activation to another application; ordering and
        // activation are separate. Verify key status only while this process is active.
        if NSApp.isActive { #expect(bar.mainWindow.isKeyWindow) }
        #expect(bar.mainWindow.frame.height > 400)
        #expect(bar.mainWindow.frame.width == 420)
        #expect(workspace.isVisible)
        #expect(settingsOpens == 0)
        if let view = bar.mainWindow.contentView,
           let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(
                to: URL(fileURLWithPath: "/tmp/inkpost-normal-main.png"))
        }
        let focus = presentation.bodyFocusRequest
        other.setFrame(bar.mainWindow.frame, display: true)
        other.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(100))
        let ordered = NSApp.orderedWindows
        let front = try #require(ordered.firstIndex(of: other))
        let back = try #require(ordered.firstIndex(of: bar.mainWindow))
        #expect(front < back)
        #expect(bar.mainWindow.isVisible)
        #expect(bar.mainWindow.level == .normal)
        #expect(!bar.mainWindow.isKeyWindow)
        bar.item.button?.performClick(nil)
        #expect(bar.mainWindow.isVisible)
        #expect(bar.mainWindow.collectionBehavior.contains(.moveToActiveSpace))
        #expect(bar.mainWindow.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(!bar.mainWindow.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(bar.mainWindow.tabbingMode == .disallowed)
        #expect(presentation.bodyFocusRequest != focus)
        #expect(settingsOpens == 0)
    }

    @Test func titlebarButtonsHideSameWindowAndSettingsDoNotReplaceIt() async throws {
        _ = NSApplication.shared
        let controller = DispatchController(service: DispatchService(), settings: DispatchSettings())
        controller.state.markdown = "Original text\n\n retained"
        var settingsOpens = 0
        let bar = makeMenuBar(controller: controller, presentation: TaskPresentation(), openSettings: { settingsOpens += 1 })
        defer { bar.stop() }
        bar.showMainWindow()
        #expect(bar.mainWindow.title == "墨驿")
        #expect(bar.mainWindow.titleVisibility == .visible)
        #expect(bar.mainWindow.standardWindowButton(.zoomButton)?.isEnabled == false)
        bar.mainWindow.performClose(nil)
        #expect(!bar.mainWindow.isVisible)
        bar.showMainWindow()
        bar.mainWindow.standardWindowButton(.miniaturizeButton)?.performClick(nil)
        #expect(!bar.mainWindow.isVisible)
        #expect(!bar.mainWindow.isMiniaturized)
        bar.showMainWindow()
        let controls = try #require(bar.mainWindow.titlebarAccessoryViewControllers.first?.view as? UpdateTitlebarControls)
        let gear = controls.gear
        gear.performClick(nil)
        #expect(settingsOpens == 1)
        #expect(bar.mainWindow.isVisible)
        #expect(controller.state.markdown == "Original text\n\n retained")
    }

    @Test func sceneWindowIsReusedForEveryReopen() {
        _ = NSApplication.shared
        let controller = DispatchController(service: DispatchService(), settings: DispatchSettings())
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 500),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let bar = makeMenuBar(controller: controller, presentation: TaskPresentation(), openSettings: {}, window: window)
        defer { bar.stop() }
        #expect(bar.mainWindow === window)
        bar.showMainWindow()
        bar.showMainWindow()
        #expect(bar.mainWindow === window)
        window.performClose(nil)
        bar.showMainWindow()
        #expect(window.isVisible)
        #expect(bar.mainWindow === window)
    }

    @Test func idleBrandGlyphIsVisuallyCentered() throws {
        let appearance = try #require(NSAppearance(named: .aqua))
        let image = NativeMenuBar.image(running: false, attention: false, opacity: 1, appearance: appearance)
        let data = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: data))
        var left = bitmap.pixelsWide, right = 0, top = bitmap.pixelsHigh, bottom = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1 {
                left = min(left, x); right = max(right, x)
                top = min(top, y); bottom = max(bottom, y)
            }
        }
        #expect(left < right)
        #expect(abs(left - (bitmap.pixelsWide - 1 - right)) <= 1)
        #expect(abs(top - (bitmap.pixelsHigh - 1 - bottom)) <= 1)
    }

    @Test func dotMatchesPrototypeColorSizeAndOpacity() throws {
        let appearance = try #require(NSAppearance(named: .aqua))
        func bitmap(alpha: Double) throws -> NSBitmapImageRep {
            let image = NativeMenuBar.image(running: true, attention: false, opacity: alpha, appearance: appearance)
            #expect(image.size == NSSize(width: 36, height: 22))
            #expect(!image.isTemplate)
            let data = try #require(image.tiffRepresentation)
            return try #require(NSBitmapImageRep(data: data))
        }
        let full = try bitmap(alpha: 1)
        let dim = try bitmap(alpha: 0.3)
        let scale = Double(full.pixelsWide) / 36
        let x = Int(28.5 * scale), y = Int(11 * scale)
        // colorAt reports calibrated RGB even for an sRGB bitmap. Check the tagged raw pixels
        // instead of converting those already-sRGB components through a second color space.
        #expect(full.colorSpace == NSColorSpace.sRGB)
        var center = [Int](repeating: 0, count: 4)
        var faded = [Int](repeating: 0, count: 4)
        full.getPixel(&center, atX: x, y: y)
        dim.getPixel(&faded, atX: x, y: y)
        #expect(abs(center[0] - 82) <= 1)
        #expect(abs(center[1] - 119) <= 1)
        #expect(abs(center[2] - 91) <= 1)
        #expect(center[3] == 255)
        #expect(abs(faded[3] - 77) <= 1)
        // Samples outside the 5pt circle remain transparent, rather than a larger glyph dot.
        #expect((full.colorAt(x: Int(25 * scale), y: y)?.alphaComponent ?? 1) < 0.01)
        #expect((full.colorAt(x: Int(32 * scale), y: y)?.alphaComponent ?? 1) < 0.01)
    }
}
