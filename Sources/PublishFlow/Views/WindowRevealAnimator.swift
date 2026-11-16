import AppKit
import OSLog

/// A noninteractive drawing surface, never a second editor or activation target.
/// The real window keeps its final size, native controls and first responder throughout.
@MainActor
final class WindowRevealAnimator {
    private weak var window: NSWindow?
    private var surface: NSWindow?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private let logger = Logger(subsystem: "com.publishflow.app", category: "window-reveal")
    private var startedAt: TimeInterval?
    private var refreshing = false
    private(set) var isRunning = false

    func prepare(_ window: NSWindow) {
        finish()
        self.window = window
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let frameView = window.contentView?.superview else { return }
        frameView.layoutSubtreeIfNeeded()
        guard let bitmap = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else {
            NSLog("Window reveal skipped: unable to allocate window snapshot")
            return
        }
        frameView.cacheDisplay(in: frameView.bounds, to: bitmap)
        let image = NSImage(size: frameView.bounds.size)
        image.addRepresentation(bitmap)
        let drawing = WindowRevealView(frame: NSRect(origin: .zero, size: window.frame.size),
                                       image: image,
                                       titleHeight: window.frame.height - window.contentLayoutRect.height)
        let surface = NSWindow(contentRect: window.frame, styleMask: .borderless,
                               backing: .buffered, defer: false)
        surface.isReleasedWhenClosed = false
        surface.backgroundColor = .clear
        surface.isOpaque = false
        surface.hasShadow = true
        surface.ignoresMouseEvents = true
        surface.isExcludedFromWindowsMenu = true
        surface.level = .normal
        surface.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .fullScreenDisallowsTiling]
        surface.contentView = drawing
        surface.setAccessibilityElement(false)
        self.surface = surface
        isRunning = true
        window.alphaValue = 0
        logger.notice("Reveal prepared")
    }

    func start() {
        guard let window, let surface, isRunning else { return }
        surface.setFrame(window.frame, display: true)
        surface.order(.above, relativeTo: window.windowNumber)
        startedAt = ProcessInfo.processInfo.systemUptime
        logger.notice("Reveal started")
        let center = NotificationCenter.default
        for name in [NSWindow.didResignKeyNotification, NSWindow.didMoveNotification,
                     NSWindow.willCloseNotification] {
            observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.finish(reason: name.rawValue) }
            })
        }
        observers.append(center.addObserver(forName: NSWindow.didResizeNotification,
                                           object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshSurface() }
        })
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification,
                                           object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish(reason: "application-deactivated") }
        })
        let started = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let window = self.window else { self?.finish(); return }
                let elapsed = ProcessInfo.processInfo.systemUptime - started
                guard window.isVisible, elapsed < 0.42,
                      !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
                    self.finish(reason: window.isVisible ? "completed-or-reduced-motion" : "hidden")
                    return
                }
                (self.surface?.contentView as? WindowRevealView)?.elapsed = elapsed
                self.surface?.invalidateShadow()
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    /// SwiftUI finalizes the fixed content height after ordering the window front.
    /// Follow that layout update without ending or restarting the reveal clock.
    private func refreshSurface() {
        guard !refreshing, isRunning, let window, let surface,
              let frameView = window.contentView?.superview else { return }
        refreshing = true
        defer { refreshing = false }
        frameView.layoutSubtreeIfNeeded()
        guard let bitmap = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else {
            logger.error("Cannot refresh window reveal snapshot after layout")
            finish(reason: "snapshot-refresh-failed")
            return
        }
        frameView.cacheDisplay(in: frameView.bounds, to: bitmap)
        let image = NSImage(size: frameView.bounds.size)
        image.addRepresentation(bitmap)
        let drawing = WindowRevealView(frame: NSRect(origin: .zero, size: window.frame.size), image: image,
                                       titleHeight: window.frame.height - window.contentLayoutRect.height)
        drawing.elapsed = startedAt.map { ProcessInfo.processInfo.systemUptime - $0 } ?? 0
        surface.setFrame(window.frame, display: true)
        surface.contentView = drawing
        logger.notice("Reveal followed content layout resize")
    }

    /// Never orders or activates the real window: hide/deactivation must remain authoritative.
    func finish(reason: String = "explicit") {
        if isRunning {
            let elapsed = startedAt.map { ProcessInfo.processInfo.systemUptime - $0 } ?? 0
            logger.notice("Reveal ended: \(reason, privacy: .public), elapsed=\(elapsed)")
        }
        startedAt = nil
        timer?.invalidate()
        timer = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        window?.alphaValue = 1
        surface?.orderOut(nil)
        surface?.close()
        surface = nil
        isRunning = false
    }
}
