import AppKit

/// Geometry follows the approved Morph Popover study; pixels stay at their native size.
@MainActor
final class WindowRevealView: NSView {
    private let image: NSImage
    private let titleHeight: CGFloat
    private let anchorX: CGFloat
    var elapsed: TimeInterval = 0 { didSet { needsDisplay = true } }

    init(frame: NSRect, image: NSImage, titleHeight: CGFloat, anchorX: CGFloat? = nil) {
        self.anchorX = anchorX ?? frame.width - 54
        self.image = image
        self.titleHeight = titleHeight
        super.init(frame: frame)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    static func shellFrame(in bounds: NSRect, anchorX: CGFloat, progress: CGFloat) -> NSRect {
        let initialWidth = min(108, bounds.width)
        let initialX = min(max(anchorX - initialWidth / 2, bounds.minX), bounds.maxX - initialWidth)
        let width = initialWidth + (bounds.width - initialWidth) * progress
        let height = 38 + (bounds.height - 38) * progress
        return NSRect(x: initialX + (bounds.minX - initialX) * progress,
                      y: bounds.maxY - height, width: width, height: height)
    }

    override func draw(_ dirtyRect: NSRect) {
        let t = min(1, elapsed / 0.42)
        let progress = t == 1 ? 1 : 1 - exp(-8 * t) * (cos(4 * t) + 2 * sin(4 * t))
        let shell = Self.shellFrame(in: bounds, anchorX: anchorX, progress: progress)
        let radius = 19 - 7 * progress
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: shell, xRadius: radius, yRadius: radius).addClip()
        NSColor(srgbRed: 252 / 255, green: 251 / 255, blue: 247 / 255, alpha: 1).setFill()
        shell.fill()
        let fade = min(1, max(0, (elapsed - 0.12) / 0.20))
        let headerHeight = 38 + (titleHeight - 38) * progress
        let header = NSRect(x: shell.minX, y: shell.maxY - headerHeight,
                            width: shell.width, height: headerHeight)
        // Preserve the native titlebar gradient using a blank vertical strip, without its title.
        image.draw(in: header,
                   from: NSRect(x: min(100, image.size.width - 1), y: image.size.height - titleHeight,
                                width: 1, height: titleHeight),
                   operation: .sourceOver, fraction: progress)
        // Crop rather than scale: editor text and native controls retain their final geometry.
        NSGraphicsContext.saveGraphicsState()
        let snapshotRegion = NSBezierPath(rect: NSRect(x: 0, y: 0, width: bounds.width,
                                                     height: bounds.height - titleHeight))
        snapshotRegion.appendRect(NSRect(x: 0, y: bounds.height - titleHeight,
                                         width: bounds.midX - 45, height: titleHeight))
        snapshotRegion.appendRect(NSRect(x: bounds.midX + 45, y: bounds.height - titleHeight,
                                         width: bounds.midX - 45, height: titleHeight))
        snapshotRegion.addClip()
        image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: fade)
        NSGraphicsContext.restoreGraphicsState()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.labelColor
        ]
        let title = "墨驿" as NSString
        let size = title.size(withAttributes: attributes)
        title.draw(at: NSPoint(x: shell.midX - size.width / 2,
                               y: bounds.maxY - headerHeight / 2 - size.height / 2),
                   withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
    }
}
