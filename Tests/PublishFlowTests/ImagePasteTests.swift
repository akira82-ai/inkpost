import AppKit
import SwiftUI
import Testing
import UniformTypeIdentifiers
@testable import PublishFlow

@MainActor
struct ImagePasteTests {
    @Test func bodyWrapsToViewportWithoutChangingPastedOrCopiedText() async throws {
        _ = NSApplication.shared
        let source = "  中文🙂 " + String(repeating: "longword", count: 60)
            + "\n\nhttps://example.com/" + String(repeating: "abcdef", count: 60) + "  \n"
        var modelText = ""
        let host = NSHostingView(rootView: PasteEditor(
            text: Binding(get: { modelText }, set: { modelText = $0 }), enabled: true,
            onImages: { _ in }, onFiles: { _ in }))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 150),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        await Task.yield()
        func findScroll(_ view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            return view.subviews.lazy.compactMap { findScroll($0) }.first
        }
        let scroll = try #require(findScroll(host))
        let view = try #require(scroll.documentView as? ImagePasteTextView)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString(source, forType: .string)
        #expect(view.readSelection(from: board, type: .string))
        let layout = try #require(view.layoutManager)
        let container = try #require(view.textContainer)
        var heights: [CGFloat] = []
        for width in [300.0, 480.0, 240.0] {
            window.setContentSize(NSSize(width: width, height: 150))
            host.layoutSubtreeIfNeeded()
            scroll.layoutSubtreeIfNeeded()
            layout.ensureLayout(for: container)
            #expect(abs(view.frame.width - scroll.contentSize.width) < 1)
            #expect(layout.usedRect(for: container).maxX <= scroll.contentSize.width + 1)
            heights.append(layout.usedRect(for: container).height)
            #expect(view.string == source)
            #expect(modelText == source)
        }
        #expect(heights[1] < heights[0])
        #expect(heights[2] > heights[0])
        view.setSelectedRange(NSRange(location: 0, length: (source as NSString).length))
        #expect(view.writeSelection(to: board, types: view.writablePasteboardTypes))
        #expect(board.string(forType: .string) == source)
        view.setSelectedRange(NSRange(location: (source as NSString).length, length: 0))
        view.insertText("继续编辑🙂", replacementRange: view.selectedRange())
        layout.ensureLayout(for: container)
        #expect(modelText == source + "继续编辑🙂")
        #expect(layout.usedRect(for: container).maxX <= scroll.contentSize.width + 1)
    }

    private func editor() -> ImagePasteTextView {
        let view = ImagePasteTextView(frame: NSRect(x: 0, y: 0, width: 384, height: 150))
        view.isRichText = false
        view.isEditable = true
        return view
    }

    @Test func bodyFocusRequestPreservesTextAndDoesNotKeepStealingFocus() async {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let view = editor()
        view.string = "保留已有正文🙂"
        view.setSelectedRange(NSRange(location: 2, length: 0))
        view.requestBodyFocus()
        window.contentView?.addSubview(view)
        await Task.yield()
        #expect(window.firstResponder === view)
        #expect(view.string == "保留已有正文🙂")
        #expect(view.selectedRange() == NSRange(location: 2, length: 0))
        let other = NSTextView(frame: .zero)
        window.contentView?.addSubview(other)
        window.makeFirstResponder(other)
        view.layout()
        await Task.yield()
        #expect(window.firstResponder === other)
        view.requestBodyFocus()
        await Task.yield()
        #expect(window.firstResponder === view)
    }

    @Test func nativePasteNegotiatesImageTypesWithoutInsertingText() throws {
        let view = editor()
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        var received: [Data] = []
        view.onImages = { received.append($0) }
        for (type, format) in [(NSPasteboard.PasteboardType.png, NSBitmapImageRep.FileType.png), (.tiff, .tiff), (.init(UTType.jpeg.identifier), .jpeg)] {
            let data = try #require(bitmap.representation(using: format, properties: [:]))
            board.clearContents(); board.setData(data, forType: type)
            let preferred = try #require(view.preferredPasteboardType(from: board.types ?? [], restrictedToTypesFrom: nil))
            #expect(view.readSelection(from: board, type: preferred))
            #expect(received.last == board.data(forType: preferred))
            #expect(view.string.isEmpty)
        }
        #expect(received.count == 3)
    }

    @Test func ordinaryTextAndReadOnlyStateRemainNative() {
        let view = editor()
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("Text and 中文", forType: .string)
        #expect(view.readSelection(from: board, type: .string))
        #expect(view.string == "Text and 中文")
        view.isEditable = false
        #expect(!view.readSelection(from: board, type: .string))
    }

    @Test func copiedImageFilesUseSharedImportPath() throws {
        let view = editor()
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("inkpost-paste-\(UUID().uuidString).png")
        try Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!.write(to: file)
        board.writeObjects([file as NSURL])
        var paths: [String] = []
        view.onFiles = { paths = $0 }
        let type = try #require(view.preferredPasteboardType(from: board.types ?? [], restrictedToTypesFrom: nil))
        #expect(view.readSelection(from: board, type: type))
        #expect(paths == [file.path])
        #expect(view.string.isEmpty)
    }
}
