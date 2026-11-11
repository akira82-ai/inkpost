import AppKit
import KeyboardShortcuts
import Observation
import OSLog

@MainActor @Observable
final class ShortcutController {
    static let defaultShortcut = KeyboardShortcuts.Shortcut(.quote, modifiers: [.command])
    static let storageKey = "Inkpost.wakeShortcut"
    // Version-pinned recorder integration: suspend OS registration while capturing,
    // including re-recording the currently active combination. Covered by tests.
    static let recordingNotification = Notification.Name("KeyboardShortcuts_recorderActiveStatusDidChange")

    var shortcut: KeyboardShortcuts.Shortcut?
    private(set) var isRegistered = false
    private(set) var message: String?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let registrar: any HotKeyRegistering
    @ObservationIgnored private var action: (() -> Void)?
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var recording = false
    @ObservationIgnored private let logger = Logger(subsystem: "com.publishflow.app", category: "shortcut")

    init(defaults: UserDefaults = .standard, registrar: (any HotKeyRegistering)? = nil) {
        self.defaults = defaults
        self.registrar = registrar ?? GlobalHotKey()
        if let data = defaults.data(forKey: Self.storageKey) {
            do { shortcut = try JSONDecoder().decode(KeyboardShortcuts.Shortcut?.self, from: data) }
            catch { shortcut = nil; message = "快捷键配置无法读取，请重新设置。" }
        } else { shortcut = Self.defaultShortcut }
    }

    func start(action: @escaping () -> Void) {
        guard self.action == nil else { return }
        self.action = action
        observer = NotificationCenter.default.addObserver(forName: Self.recordingNotification, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                self?.setRecording(note.userInfo?["isActive"] as? Bool == true)
            }
        }
        activate()
    }

    func save(_ value: KeyboardShortcuts.Shortcut?) {
        do {
            let data = try JSONEncoder().encode(value)
            defaults.set(data, forKey: Self.storageKey)
            shortcut = value
            message = nil
            activate()
        } catch { message = "快捷键保存失败，请重试。"; logger.error("Shortcut encoding failed: \(error.localizedDescription, privacy: .public)") }
    }

    func retry() { activate() }

    private func setRecording(_ active: Bool) {
        recording = active
        activate()
    }

    private func activate() {
        registrar.unregister()
        isRegistered = false
        guard !recording, let shortcut, let action else { return }
        message = nil
        guard !shortcut.isTakenBySystem else {
            message = "这个快捷键已被系统使用，请更换组合键。"
            return
        }
        do {
            try registrar.register(shortcut, action: action)
            isRegistered = true
        } catch {
            message = error.localizedDescription
            logger.error("Wake shortcut registration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        registrar.unregister()
        isRegistered = false
        action = nil
        recording = false
    }
}
