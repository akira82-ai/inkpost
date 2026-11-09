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
