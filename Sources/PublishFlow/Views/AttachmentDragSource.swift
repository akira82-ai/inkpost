import AppKit
import SwiftUI

/// AppKit provides a session-end callback on macOS 14, including cancelled/outside drops.
struct AttachmentDragSource: NSViewRepresentable {
    static let pasteboardType = NSPasteboard.PasteboardType("com.publishflow.attachment-order")
    let path: String
    let data: Data?
    let editable: Bool
    let started: () -> Void
    let ended: () -> Void
    let clicked: () -> Void
    let removed: () -> Void
    let hovered: (Bool) -> Void
    let accepts: (String) -> Bool
    let targeted: (Bool) -> Void
    let dropped: (String) -> Void

    func makeNSView(context: Context) -> AttachmentDragView { AttachmentDragView() }
    func updateNSView(_ view: AttachmentDragView, context: Context) {
        view.path = path
        view.image = data.flatMap(NSImage.init(data:))
        view.editable = editable
        view.started = started
        view.ended = ended
        view.clicked = clicked
        view.removed = removed
        view.hovered = hovered
        view.accepts = accepts
        view.targeted = targeted
        view.dropped = dropped
    }
}

class AttachmentDragView: NSView, NSDraggingSource {
    var path = ""
    var image: NSImage?
    var editable = false
    var started: () -> Void = {}
    var ended: () -> Void = {}
    var clicked: () -> Void = {}
    var removed: () -> Void = {}
    var hovered: (Bool) -> Void = { _ in }
    var accepts: (String) -> Bool = { _ in false }
    var targeted: (Bool) -> Void = { _ in }
    var dropped: (String) -> Void = { _ in }
    private var mouseDownPoint: NSPoint?
    private var dragging = false
    private var hoverArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([AttachmentDragSource.pasteboardType])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }
    override func mouseEntered(with event: NSEvent) { hovered(true) }
    override func mouseExited(with event: NSEvent) { hovered(false) }

    private func isRemovePoint(_ point: NSPoint) -> Bool {
        editable && NSRect(x: bounds.maxX - 21, y: bounds.maxY - 21, width: 19, height: 19).contains(point)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint, !dragging else { return }
        guard hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) >= 4 else { return }
        mouseDownPoint = nil
        guard !isRemovePoint(convert(start, from: nil)) else { return }
        guard editable, let image else { return }
        // A private type prevents an unsuccessful image drop from pasting a file path into the body.
        let writer = NSPasteboardItem()
        writer.setString(path, forType: AttachmentDragSource.pasteboardType)
        let item = NSDraggingItem(pasteboardWriter: writer)
        item.setDraggingFrame(bounds, contents: image)
        dragging = true
        started()
        beginDraggingSession(with: [item], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownPoint = nil }
        let point = convert(event.locationInWindow, from: nil)
        guard !dragging, let start = mouseDownPoint, bounds.contains(point) else { return }
        // Native representable views receive mouse events above SwiftUI's overlaid remove button.
        if isRemovePoint(convert(start, from: nil)) && isRemovePoint(point) { removed() }
        else { clicked() }
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        editable && context == .withinApplication ? .move : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        dragging = false
        mouseDownPoint = nil
        ended()
    }

    private func sourcePath(_ sender: any NSDraggingInfo) -> String? {
        guard editable, sender.draggingSource is AttachmentDragView,
              sender.draggingSourceOperationMask.contains(.move),
              let source = sender.draggingPasteboard.string(forType: AttachmentDragSource.pasteboardType),
              accepts(source) else { return nil }
        return source
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let source = sourcePath(sender)
        targeted(source != nil && source != path)
        return source == nil ? [] : .move
    }
    override func draggingExited(_ sender: (any NSDraggingInfo)?) { targeted(false) }
    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool { sourcePath(sender) != nil }
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        defer { targeted(false) }
        guard let source = sourcePath(sender) else { return false }
        dropped(source)
        return true
    }
    override func draggingEnded(_ sender: any NSDraggingInfo) { targeted(false) }
}
