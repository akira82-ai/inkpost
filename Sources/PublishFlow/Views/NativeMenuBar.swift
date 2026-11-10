import AppKit
import CoreText
import SwiftUI
import Observation
import PublishKit

/// Own the status button directly: animation never re-renders a SwiftUI label or its layout.
@MainActor
final class NativeMenuBar: NSObject, NSWindowDelegate {
    let item: NSStatusItem
    let mainWindow: NSWindow
    private let controller: DispatchController
    private let presentation: TaskPresentation
    private let showSettings: () -> Void
    private var pulseTimer: Timer?
    private var accessibilityObserver: NSObjectProtocol?
    private var appearanceObservation: NSKeyValueObservation?
    private var frames: [NSImage] = []
    private var frame = 0
    private var startedAt: TimeInterval = 0
    private var observing = true
    private var lastMessage: String?
    private var lastRunning = false
    private var lastAttention = false
    private(set) var frameUpdates = 0
    var isAnimating: Bool { pulseTimer != nil }

    init(controller: DispatchController, presentation: TaskPresentation, openSettings: @escaping () -> Void, window: NSWindow, updates: UpdateController? = nil) {
        mainWindow = window
        self.controller = controller
        self.presentation = presentation
        self.showSettings = openSettings
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        guard let button = item.button else { return }
        button.target = self
        button.action = #selector(showMainWindow)
        button.imagePosition = .imageLeading
        button.font = .menuBarFont(ofSize: 0)
        mainWindow.title = "墨驿"
        mainWindow.styleMask = [.titled, .closable, .miniaturizable]
        mainWindow.titleVisibility = .visible
        mainWindow.titlebarAppearsTransparent = false
        mainWindow.standardWindowButton(.closeButton)?.isHidden = false
        mainWindow.standardWindowButton(.miniaturizeButton)?.isHidden = false
        mainWindow.standardWindowButton(.miniaturizeButton)?.target = self
        mainWindow.standardWindowButton(.miniaturizeButton)?.action = #selector(minimizeToBackground)
        mainWindow.standardWindowButton(.zoomButton)?.isHidden = false
        mainWindow.standardWindowButton(.zoomButton)?.isEnabled = false
        // Move the one window to the active Space on invocation; never join all Spaces.
        // Auxiliary fullscreen presentation permits invocation over another app's fullscreen Space.
        mainWindow.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .fullScreenDisallowsTiling]
        mainWindow.tabbingMode = .disallowed
        mainWindow.isReleasedWhenClosed = false
        mainWindow.level = .normal
        mainWindow.hidesOnDeactivate = false
        mainWindow.delegate = self
        let accessory = NSTitlebarAccessoryViewController()
        let gear = NSButton(image: NSImage(systemSymbolName: "gearshape", accessibilityDescription: "设置")!,
                            target: self, action: #selector(openSettingsWindow))
        gear.isBordered = false
        gear.toolTip = "设置"
        accessory.view = UpdateTitlebarControls(gear: gear, updates: updates)
        accessory.layoutAttribute = .right
        mainWindow.addTitlebarAccessoryViewController(accessory)
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateAnimation() }
        }
        appearanceObservation = button.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.updateAnimation() }
        }
        refreshAndObserve()
    }

    private func refreshAndObserve() {
        guard observing else { return }
        let state = withObservationTracking {
            let status = MenuBarStatus(model: controller.state)
            return (status.message, status.isRunning, status.needsAttention)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.refreshAndObserve() }
        }
        guard state.0 != lastMessage || state.1 != lastRunning || state.2 != lastAttention else { return }
        let animationChanged = state.1 != lastRunning || state.2 != lastAttention || lastMessage == nil
        lastMessage = state.0
        lastRunning = state.1
        lastAttention = state.2
        guard let button = item.button else { return }
        // Channel events change copy here; the animation timer never writes title or length.
        button.title = state.0.isEmpty ? "" : " " + state.0
        button.imagePosition = state.0.isEmpty ? .imageOnly : .imageLeading
        button.setAccessibilityLabel(state.0.isEmpty ? "墨驿" : "墨驿，" + state.0)
        button.toolTip = state.0.isEmpty ? "打开墨驿" : state.0 + "，点击恢复窗口"
        if animationChanged { updateAnimation() }
        let titleWidth = (button.title as NSString).size(withAttributes: [.font: button.font ?? NSFont.menuBarFont(ofSize: 0)]).width
        item.length = state.0.isEmpty ? NSStatusItem.squareLength
            : ceil(titleWidth + (state.1 || state.2 ? 36 : 22) + 16)
    }

    private func updateAnimation() {
        pulseTimer?.invalidate()
        pulseTimer = nil
        frame = 0
        guard let button = item.button else { return }
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        frames = (0..<26).map { index in
            let alpha = 0.65 + 0.35 * cos(Double(index) / 26 * 2 * .pi)
            return Self.image(running: lastRunning, attention: lastAttention,
                              opacity: alpha, appearance: button.effectiveAppearance)
        }
        button.image = frames[0]
        guard lastRunning, !reduced, observing else { return }
        startedAt = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advanceFrame() }
        }
        pulseTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func advanceFrame() {
        guard observing, lastRunning, let button = item.button, !frames.isEmpty else { return }
        let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
        let next = Int(elapsed / 1.3 * 26) % frames.count
        guard next != frame else { return }
        frame = next
        button.image = frames[next]
        frameUpdates += 1
    }

    /// The 5pt dot is drawn into a fixed-size, non-template image to preserve #52775B and alpha.
    static func image(running: Bool, attention: Bool, opacity: Double, appearance: NSAppearance) -> NSImage {
        let size = NSSize(width: running || attention ? 36 : 22, height: 22)
        let image = NSImage(size: size)
        for scale in [1, 2] {
            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: nil, width: Int(size.width) * scale,
                                          height: Int(size.height) * scale, bitsPerComponent: 8,
                                          bytesPerRow: 0, space: colorSpace,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                preconditionFailure("Cannot allocate menu-bar image context")
            }
            context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            appearance.performAsCurrentDrawingAppearance {
                if !running && !attention {
                    let line = CTLineCreateWithAttributedString(NSAttributedString(string: "墨", attributes: [
                        .font: NSFont(name: "Songti SC", size: 18) ?? NSFont.systemFont(ofSize: 18),
                        .foregroundColor: NSColor.labelColor
                    ]))
                    let bounds = CTLineGetImageBounds(line, context)
                    context.textPosition = CGPoint(x: size.width / 2 - bounds.midX,
                                                   y: size.height / 2 - bounds.midY)
                    CTLineDraw(line, context)
                } else {
                ("墨" as NSString).draw(at: NSPoint(x: 1, y: 0), withAttributes: [
                    .font: NSFont(name: "Songti SC", size: 18) ?? NSFont.systemFont(ofSize: 18),
                    .foregroundColor: NSColor.labelColor
                ])
                }
                if running {
                    context.setFillColor(CGColor(srgbRed: 82.0 / 255, green: 119.0 / 255,
                                                 blue: 91.0 / 255, alpha: opacity))
                    context.fillEllipse(in: CGRect(x: 26, y: 8.5, width: 5, height: 5))
                } else if attention {
                    let color = NSColor(srgbRed: 156.0 / 255, green: 113.0 / 255, blue: 69.0 / 255, alpha: 1)
                    color.setStroke()
                    let ring = NSBezierPath(ovalIn: NSRect(x: 23, y: 5.5, width: 11, height: 11))
                    ring.lineWidth = 1
                    ring.stroke()
                    ("!" as NSString).draw(at: NSPoint(x: 27, y: 6), withAttributes: [
                        .font: NSFont.systemFont(ofSize: 8), .foregroundColor: color
                    ])
                }
            }
            NSGraphicsContext.restoreGraphicsState()
            guard let cgImage = context.makeImage() else { preconditionFailure("Cannot draw menu-bar image") }
            let representation = NSBitmapImageRep(cgImage: cgImage)
            representation.size = size
            image.addRepresentation(representation)
        }
        image.isTemplate = false
        return image
    }

    /// All explicit entry points come here, including clicks while covered or on another Space.
    @objc func showMainWindow() {
        // Order before activation so the window moves here instead of activating its old Space.
        if !mainWindow.isVisible || !mainWindow.isOnActiveSpace { positionMainWindow() }
        mainWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        presentation.bodyFocusRequest = UUID()
    }

    private func positionMainWindow() {
        let anchorWindow = item.button?.window
        let anchor = item.button.flatMap { button in
            anchorWindow?.convertToScreen(button.convert(button.bounds, to: nil))
        }
        let screen = anchorWindow?.screen ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        mainWindow.contentView?.layoutSubtreeIfNeeded()
        let fitting = mainWindow.contentView?.fittingSize ?? NSSize(width: 420, height: 540)
        let width = min(420, visible.width - 24)
        let titleHeight = mainWindow.frame.height - mainWindow.contentLayoutRect.height
        let height = min(max(1, fitting.height) + titleHeight, visible.height - 16)
        let x = min(max((anchor?.midX ?? visible.midX) - width / 2, visible.minX + 8), visible.maxX - width - 8)
        let y = max(visible.minY + 8, min(anchor?.minY ?? visible.maxY, visible.maxY) - 8 - height)
        mainWindow.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }

    private func hideMainWindow() {
        mainWindow.orderOut(nil)
    }

    @objc private func openSettingsWindow() { showSettings() }
    @objc private func minimizeToBackground() { hideMainWindow() }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hideMainWindow()
        return false
    }

    func stop() {
        observing = false
        pulseTimer?.invalidate()
        pulseTimer = nil
        if let accessibilityObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver)
        }
        accessibilityObserver = nil
        appearanceObservation = nil
        mainWindow.delegate = nil
        mainWindow.close()
        NSStatusBar.system.removeStatusItem(item)
    }
}

/// Install on the sole SwiftUI main window; settings never bootstrap another editor.
struct MenuBarInstallation: View {
    let lifecycle: AppLifecycle
    let controller: DispatchController
    let presentation: TaskPresentation
    var updates: UpdateController? = nil
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        WindowReader { window in
            lifecycle.installMenuBar(controller: controller, presentation: presentation, window: window, updates: updates) {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            }
        }.frame(width: 0, height: 0)
    }
}
