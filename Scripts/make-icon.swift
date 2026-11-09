import AppKit
import CoreText

// Generate the prototype's ink/paper brand mark at all standard macOS icon resolutions.
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for (name, points, scale) in [
    ("icon_16x16", 16, 1), ("icon_16x16@2x", 16, 2),
    ("icon_32x32", 32, 1), ("icon_32x32@2x", 32, 2),
    ("icon_128x128", 128, 1), ("icon_128x128@2x", 128, 2),
    ("icon_256x256", 256, 1), ("icon_256x256@2x", 256, 2),
    ("icon_512x512", 512, 1), ("icon_512x512@2x", 512, 2)
] {
    let pixels = points * scale
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    NSColor(srgbRed: 37/255.0, green: 41/255.0, blue: 35/255.0, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896),
                 xRadius: 210, yRadius: 210).fill()
    let font = NSFont(name: "Songti SC", size: 600) ?? NSFont.systemFont(ofSize: 600)
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: "墨", attributes: [
        .font: font, .foregroundColor: NSColor(srgbRed: 252/255.0, green: 251/255.0, blue: 247/255.0, alpha: 1)
    ]))
    let glyphBounds = CTLineGetImageBounds(line, context.cgContext)
    context.cgContext.textPosition = CGPoint(x: 512 - glyphBounds.midX, y: 512 - glyphBounds.midY)
    CTLineDraw(line, context.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    let data = bitmap.representation(using: .png, properties: [:])!
    try data.write(to: directory.appendingPathComponent(name + ".png"))
}
