import AppKit
import Testing
import PublishKit
@testable import PublishFlow

@MainActor
struct NativeMenuBarTests {
    @Test func nativeFramesAdvanceWithoutChangingCopyOrWidthAndStopAtCompletion() async throws {
        _ = NSApplication.shared
        let controller = DispatchController(service: DispatchService(), settings: DispatchSettings())
        let bar = NativeMenuBar(controller: controller, presentation: TaskPresentation(), openWorkspace: {})
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

    @Test func compactStaysOpenAcrossProgressAndAllTerminalStates() async throws {
        _ = NSApplication.shared
        let controller = DispatchController(service: DispatchService(), settings: DispatchSettings())
        let model = controller.state
        let presentation = TaskPresentation()
        let bar = NativeMenuBar(controller: controller, presentation: presentation, openWorkspace: {})
        let other = NSWindow(contentRect: NSRect(x: 20, y: 20, width: 200, height: 120),
                             styleMask: [.titled], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        defer { bar.stop(); other.close() }
        #expect(type(of: bar.compactWindow) == NSWindow.self)
        #expect(bar.compactWindow.level == .normal)
        #expect(!bar.compactWindow.hidesOnDeactivate)
        bar.item.button?.performClick(nil)
        try await Task.sleep(for: .milliseconds(350))
        #expect(bar.compactWindow.isVisible)
        // Invalid input never starts a task or hides the UI.
        model.markdown = ""
        controller.dispatch()
        #expect(model.overallPhase == .pending)
        #expect(bar.compactWindow.isVisible)
        // Accepted start hides once.
        model.taskID = UUID()
        model.overallPhase = .preparing
        model.currentPlatform = .zhihu
        let hiddenDeadline = Date().addingTimeInterval(1)
        while bar.compactWindow.isVisible && Date() < hiddenDeadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!bar.compactWindow.isVisible)
        // User restores the compact window while work continues.
        bar.item.button?.performClick(nil)
        try await Task.sleep(for: .milliseconds(350))
        #expect(bar.compactWindow.isVisible)
        model.currentPlatform = .x
        other.makeKeyAndOrderFront(nil)
        for phase in [TargetPhase.awaitingConfirm, .failed, .cancelled, .needLogin] {
            model.overallPhase = phase
            model.currentPlatform = nil
            try await Task.sleep(for: .milliseconds(50))
            #expect(bar.compactWindow.isVisible)
        }
        // Explicit menu click still closes it.
        bar.item.button?.performClick(nil)
        let deadline = Date().addingTimeInterval(1)
        while bar.compactWindow.isVisible && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!bar.compactWindow.isVisible)
    }

    @Test func compactIsAnOrdinaryWindowAndCanBeCovered() async throws {
        _ = NSApplication.shared
        let previousPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        defer { NSApp.setActivationPolicy(previousPolicy) }
        let controller = DispatchController(service: DispatchService(), settings: DispatchSettings())
        let presentation = TaskPresentation()
        let workspace = NSWindow(contentRect: NSRect(x: 20, y: 20, width: 500, height: 500),
                                 styleMask: [.titled], backing: .buffered, defer: false)
        workspace.isReleasedWhenClosed = false
        var fullOpens = 0
        let bar = NativeMenuBar(controller: controller, presentation: presentation, openWorkspace: { fullOpens += 1 })
        let other = NSWindow(contentRect: bar.compactWindow.frame, styleMask: [.titled], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        defer { bar.stop(); workspace.close(); other.close() }
        workspace.orderFront(nil)
        bar.item.button?.performClick(nil)
        try await Task.sleep(for: .milliseconds(100))
        #expect(type(of: bar.compactWindow) == NSWindow.self)
        #expect(!(bar.compactWindow is NSPanel))
        #expect(bar.compactWindow.level == .normal)
        #expect(bar.compactWindow.canBecomeKey)
        // The CLI test runner can lose activation to another application; ordering and
        // activation are separate. Verify key status only while this process is active.
        if NSApp.isActive { #expect(bar.compactWindow.isKeyWindow) }
        #expect(bar.compactWindow.frame.height > 400)
        #expect(bar.compactWindow.frame.width == 420)
        #expect(workspace.isVisible)
        #expect(fullOpens == 0)
        if let view = bar.compactWindow.contentView,
           let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(
                to: URL(fileURLWithPath: "/tmp/inkpost-normal-compact.png"))
        }
        let focus = presentation.compactFocusRequest
        other.setFrame(bar.compactWindow.frame, display: true)
        other.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(100))
        let ordered = NSApp.orderedWindows
        let front = try #require(ordered.firstIndex(of: other))
        let back = try #require(ordered.firstIndex(of: bar.compactWindow))
        #expect(front < back)
        #expect(bar.compactWindow.isVisible)
        #expect(bar.compactWindow.level == .normal)
        #expect(!bar.compactWindow.isKeyWindow)
        bar.item.button?.performClick(nil)
        #expect(!bar.compactWindow.isVisible)
        bar.item.button?.performClick(nil)
        #expect(bar.compactWindow.isVisible)
        #expect(presentation.compactFocusRequest != focus)
        #expect(fullOpens == 0)
    }

    @Test func titlebarButtonsHideSameWindowAndSettingsDoNotReplaceIt() async throws {
        _ = NSApplication.shared
        let controller = DispatchController(service: DispatchService(), settings: DispatchSettings())
        controller.state.markdown = "Original text\n\n retained"
        var settingsOpens = 0
        let bar = NativeMenuBar(controller: controller, presentation: TaskPresentation(), openWorkspace: { settingsOpens += 1 })
        defer { bar.stop() }
        bar.showMainWindow()
        #expect(bar.compactWindow.title == "墨驿")
        #expect(bar.compactWindow.titleVisibility == .visible)
        #expect(bar.compactWindow.standardWindowButton(.zoomButton)?.isEnabled == false)
        bar.compactWindow.performClose(nil)
        #expect(!bar.compactWindow.isVisible)
        bar.showMainWindow()
        bar.compactWindow.standardWindowButton(.miniaturizeButton)?.performClick(nil)
        #expect(!bar.compactWindow.isVisible)
        #expect(!bar.compactWindow.isMiniaturized)
        bar.showMainWindow()
        let gear = try #require(bar.compactWindow.titlebarAccessoryViewControllers.first?.view as? NSButton)
        gear.performClick(nil)
        #expect(settingsOpens == 1)
        #expect(bar.compactWindow.isVisible)
        #expect(controller.state.markdown == "Original text\n\n retained")
    }

    @Test func sceneWindowIsReusedForEveryReopen() {
        _ = NSApplication.shared
        let controller = DispatchController(service: DispatchService(), settings: DispatchSettings())
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 500),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let bar = NativeMenuBar(controller: controller, presentation: TaskPresentation(), openWorkspace: {}, window: window)
        defer { bar.stop() }
        #expect(bar.compactWindow === window)
        bar.showMainWindow()
        bar.showMainWindow()
        #expect(bar.compactWindow === window)
        window.performClose(nil)
        bar.showMainWindow()
        #expect(window.isVisible)
        #expect(bar.compactWindow === window)
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
