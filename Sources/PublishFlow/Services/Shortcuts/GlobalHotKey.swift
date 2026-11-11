import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts

@MainActor
protocol HotKeyRegistering: AnyObject {
    func register(_ shortcut: KeyboardShortcuts.Shortcut, action: @escaping () -> Void) throws
    func unregister()
}

/// The recorder library's high-level listener hides registration failures. Keep the
/// OS registration here so a saved shortcut cannot be mistaken for an active one.
@MainActor
final class GlobalHotKey: HotKeyRegistering {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var action: (() -> Void)?
    private let signature: OSType = 0x494E4B50 // INKP

    struct RegistrationError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            "快捷键注册失败，可能已被其他应用占用，请更换组合键。（\(status)）"
        }
    }

    func register(_ shortcut: KeyboardShortcuts.Shortcut, action: @escaping () -> Void) throws {
        unregister()
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            return MainActor.assumeIsolated {
                let owner = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
                var id = EventHotKeyID()
                let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
                guard status == noErr, id.signature == owner.signature, id.id == 1 else {
                    return OSStatus(eventNotHandledErr)
                }
                owner.action?()
                return noErr
            }
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard installed == noErr else { unregister(); throw RegistrationError(status: installed) }
        let status = RegisterEventHotKey(UInt32(shortcut.carbonKeyCode), UInt32(shortcut.carbonModifiers),
            EventHotKeyID(signature: signature, id: 1), GetApplicationEventTarget(), 0, &hotKey)
        guard status == noErr else { unregister(); throw RegistrationError(status: status) }
        self.action = action
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
        action = nil
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
