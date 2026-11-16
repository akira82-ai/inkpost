import AppKit
import Testing
import SwiftUI
import PublishKit
@testable import PublishFlow

@MainActor
struct WindowRevealTests {
    @Test func capsuleTracksIconAndExpandsInsideWindowBounds() {
        let bounds = NSRect(x: 0, y: 0, width: 420, height: 560)
        for anchor: CGFloat in [12, 54, 210, 366, 408] {
            let initial = WindowRevealView.shellFrame(in: bounds, anchorX: anchor, progress: 0)
            if anchor >= 54 && anchor <= 366 { #expect(initial.midX == anchor) }
            #expect(bounds.contains(initial))
            let middle = WindowRevealView.shellFrame(in: bounds, anchorX: anchor, progress: 0.5)
            #expect(bounds.contains(middle))
            #expect(middle.maxY == bounds.maxY)
            #expect(WindowRevealView.shellFrame(in: bounds, anchorX: anchor, progress: 1) == bounds)
        }
    }
    private func makeWindow() -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 420, height: 500),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }

    @Test func completionPreservesFrameResponderAndOrdinaryWindow() async throws {
        let window = makeWindow()
        let field = NSTextField(string: "Draft remains unchanged")
        window.contentView?.addSubview(field)
        let animator = WindowRevealAnimator()
        defer { animator.finish(); window.close() }
        let frame = window.frame
        animator.prepare(window)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(field)
        let responder = window.firstResponder
        animator.start()
        try await Task.sleep(for: .milliseconds(550))
        #expect(!animator.isRunning)
        #expect(window.alphaValue == 1)
        #expect(window.frame == frame)
        #expect(window.isVisible)
        #expect(window.level == .normal)
        #expect(window.firstResponder === responder)
        #expect(field.stringValue == "Draft remains unchanged")
    }

    @Test func hideAndRepeatedPreparationNeverResurrectWindow() async throws {
        let window = makeWindow()
        let animator = WindowRevealAnimator()
        defer { animator.finish(); window.close() }
        for _ in 0..<3 {
            animator.prepare(window)
            window.orderFront(nil)
            animator.start()
            animator.finish()
            #expect(window.alphaValue == 1)
        }
        animator.prepare(window)
        window.orderFront(nil)
        animator.start()
        window.orderOut(nil)
        try await Task.sleep(for: .milliseconds(80))
        #expect(!animator.isRunning)
        #expect(!window.isVisible)
        #expect(window.alphaValue == 1)
    }

    @Test func deactivationFinishesWithoutReorderingOrActivating() {
        let window = makeWindow()
        let animator = WindowRevealAnimator()
        defer { animator.finish(); window.close() }
        animator.prepare(window)
        window.orderFront(nil)
        animator.start()
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        #expect(!animator.isRunning)
        #expect(window.alphaValue == 1)
        #expect(window.isVisible)
    }

    @Test func deferredContentResizeDoesNotCancelReveal() async throws {
        let window = makeWindow()
        let animator = WindowRevealAnimator()
        defer { animator.finish(); window.close() }
        animator.prepare(window)
        window.makeKeyAndOrderFront(nil)
        animator.start()
        window.setContentSize(NSSize(width: 420, height: 560))
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            #expect(animator.isRunning)
            #expect(window.alphaValue == 0)
            try await Task.sleep(for: .milliseconds(80))
            #expect(animator.isRunning)
        }
        try await Task.sleep(for: .milliseconds(450))
        #expect(!animator.isRunning)
        #expect(window.alphaValue == 1)
        #expect(window.contentLayoutRect.height == 560)
    }

    @Test func renderProductionComposerForVisualReview() throws {
        let window = makeWindow()
        defer { window.close() }
        let controller = DispatchController(service: DispatchService(), settings: DispatchSettings())
        controller.state.markdown = "一个好想法，值得寄出去。\n\n文字保持原来的大小。"
        window.contentViewController = NSHostingController(rootView:
            CompactView(model: controller.state, controller: controller, presentation: TaskPresentation()))
        window.setContentSize(NSSize(width: 420, height: 500))
        let view = try #require(window.contentView?.superview)
        view.layoutSubtreeIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(bitmap)
        for (name, elapsed) in [("capsule", 0.0), ("expanding", 0.16), ("complete", 0.42)] {
            let drawing = WindowRevealView(frame: view.bounds, image: image,
                                          titleHeight: window.frame.height - window.contentLayoutRect.height)
            drawing.elapsed = elapsed
            let output = try #require(drawing.bitmapImageRepForCachingDisplay(in: drawing.bounds))
            drawing.cacheDisplay(in: drawing.bounds, to: output)
            let png = try #require(output.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: "/tmp/inkpost53-\(name).png"))
        }
    }
}
