import AppKit
import Testing
@testable import PublishFlow

@MainActor
struct AttachmentDragTests {
    private func event(_ type: NSEvent.EventType, x: CGFloat = 10, y: CGFloat = 10) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: y), modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    }

    @Test func clickAndSmallMovementStillOpenPreview() throws {
        let view = RecordingDragView(frame: NSRect(x: 0, y: 0, width: 60, height: 60))
        var clicks = 0
        view.clicked = { clicks += 1 }
        view.mouseDown(with: try event(.leftMouseDown))
        view.mouseDragged(with: try event(.leftMouseDragged, x: 12))
        view.mouseUp(with: try event(.leftMouseUp, x: 12))
        #expect(clicks == 1)
        #expect(view.items.isEmpty)
    }

    @Test func cancelledAndSuccessfulSessionsClearStateAndCanDragAgain() throws {
        let view = RecordingDragView(frame: NSRect(x: 0, y: 0, width: 60, height: 60))
        view.path = "/tmp/A.png"
        view.image = NSImage(size: NSSize(width: 60, height: 60))
        view.editable = true
        var active = false
        var clicks = 0
        view.started = { active = true }
        view.ended = { active = false }
        view.clicked = { clicks += 1 }
        for operation: NSDragOperation in [[], .move] {
            view.mouseDown(with: try event(.leftMouseDown))
            view.mouseDragged(with: try event(.leftMouseDragged, x: 20))
            #expect(active)
            #expect(view.items.count == 1)
            let writer = try #require(view.items.first?.item as? NSPasteboardItem)
            #expect(writer.string(forType: AttachmentDragSource.pasteboardType) == "/tmp/A.png")
            #expect(writer.string(forType: .string) == nil)
            #expect(view.draggingSession(view.session, sourceOperationMaskFor: .withinApplication) == .move)
            #expect(view.draggingSession(view.session, sourceOperationMaskFor: .outsideApplication).isEmpty)
            view.draggingSession(view.session, endedAt: .zero, operation: operation)
            view.mouseUp(with: try event(.leftMouseUp))
            #expect(!active)
            #expect(clicks == 0)
        }
    }

    @Test func disabledOrMissingPreviewCannotStartDrag() throws {
        let view = RecordingDragView(frame: NSRect(x: 0, y: 0, width: 60, height: 60))
        view.image = NSImage(size: NSSize(width: 60, height: 60))
        var starts = 0
        view.started = { starts += 1 }
        for editable in [false, true] {
            view.editable = editable
            if editable { view.image = nil }
            view.mouseDown(with: try event(.leftMouseDown))
            view.mouseDragged(with: try event(.leftMouseDragged, x: 20))
            #expect(view.items.isEmpty)
            #expect(starts == 0)
        }
    }

    @Test func nativeDestinationAcceptsOnlyValidLocalImagesAndClearsMarker() {
        let target = AttachmentDragView()
        target.path = "C"
        target.editable = true
        target.accepts = { ["A", "B", "C"].contains($0) }
        var highlighted = false
        var drops: [String] = []
        target.targeted = { highlighted = $0 }
        target.dropped = { drops.append($0) }
        let info = ImageDragInfo()
        defer { info.draggingPasteboard.releaseGlobally() }
        info.draggingPasteboard.setString("A", forType: AttachmentDragSource.pasteboardType)
        #expect(target.registeredDraggedTypes == [AttachmentDragSource.pasteboardType])
        #expect(target.draggingEntered(info) == .move)
        #expect(highlighted)
        #expect(target.prepareForDragOperation(info))
        #expect(target.performDragOperation(info))
        #expect(drops == ["A"])
        #expect(!highlighted)
        #expect(target.draggingUpdated(info) == .move)
        target.draggingExited(info)
        #expect(!highlighted)
        info.draggingPasteboard.setString("C", forType: AttachmentDragSource.pasteboardType)
        #expect(target.draggingEntered(info) == .move)
        #expect(!highlighted)
        info.draggingPasteboard.setString("missing", forType: AttachmentDragSource.pasteboardType)
        #expect(target.draggingUpdated(info).isEmpty)
        #expect(!target.performDragOperation(info))
        info.draggingPasteboard.setString("B", forType: AttachmentDragSource.pasteboardType)
        info.draggingSource = nil
        #expect(target.draggingEntered(info).isEmpty)
        info.draggingSource = AttachmentDragView()
        #expect(target.draggingEntered(info) == .move)
        target.editable = false // State changed between entry and drop.
        #expect(!target.prepareForDragOperation(info))
        #expect(!target.performDragOperation(info))
        #expect(!highlighted)
        #expect(drops == ["A"])
    }

    @Test func nativeOverlayRoutesRemoveWithoutPreviewOrDragAndHonorsDisabledState() throws {
        let view = RecordingDragView(frame: NSRect(x: 0, y: 0, width: 60, height: 60))
        view.editable = true
        view.image = NSImage(size: NSSize(width: 60, height: 60))
        var removes = 0
        var previews = 0
        view.removed = { removes += 1 }
        view.clicked = { previews += 1 }
        view.mouseDown(with: try event(.leftMouseDown, x: 48, y: 48))
        view.mouseUp(with: try event(.leftMouseUp, x: 48, y: 48))
        #expect(removes == 1)
        #expect(previews == 0)
        view.mouseDown(with: try event(.leftMouseDown, x: 48, y: 48))
        view.mouseDragged(with: try event(.leftMouseDragged, x: 30, y: 30))
        view.mouseUp(with: try event(.leftMouseUp, x: 30, y: 30))
        #expect(view.items.isEmpty)
        #expect(removes == 1 && previews == 0)
        view.editable = false
        view.mouseDown(with: try event(.leftMouseDown, x: 48, y: 48))
        view.mouseUp(with: try event(.leftMouseUp, x: 48, y: 48))
        #expect(removes == 1)
        #expect(previews == 1)
    }
}

@MainActor
private final class ImageDragInfo: NSObject, NSDraggingInfo {
    var draggingDestinationWindow: NSWindow? { nil }
    var draggingSourceOperationMask: NSDragOperation { .move }
    var draggingLocation: NSPoint { .zero }
    var draggedImageLocation: NSPoint { .zero }
    nonisolated var draggedImage: NSImage? { nil }
    let draggingPasteboard = NSPasteboard.withUniqueName()
    var draggingSource: Any? = AttachmentDragView()
    var draggingSequenceNumber: Int { 1 }
    var draggingFormation: NSDraggingFormation = .none
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    nonisolated override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func resetSpringLoading() {}
    func enumerateDraggingItems(options: NSDraggingItemEnumerationOptions, for view: NSView?, classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any], using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
}

@MainActor
private final class RecordingDragView: AttachmentDragView {
    // Opaque callback argument only; no real system drag is started by this test double.
    private static let testSession = NSDraggingSession()
    var session: NSDraggingSession { Self.testSession }
    var items: [NSDraggingItem] = []
    override func beginDraggingSession(with items: [NSDraggingItem], event: NSEvent, source: any NSDraggingSource) -> NSDraggingSession {
        self.items = items
        return session
    }
}
