import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts
import PublishKit
import SwiftUI
import Testing
@testable import PublishFlow

@MainActor @Suite(.serialized)
struct ShortcutTests {
    private final class Registrar: HotKeyRegistering {
        var registered: KeyboardShortcuts.Shortcut?
        var action: (() -> Void)?
        var fail = false
        func register(_ shortcut: KeyboardShortcuts.Shortcut, action: @escaping () -> Void) throws {
            if fail { throw GlobalHotKey.RegistrationError(status: OSStatus(eventHotKeyExistsErr)) }
            registered = shortcut; self.action = action
        }
        func unregister() { registered = nil; action = nil }
    }

    private func preferences() -> UserDefaults {
        UserDefaults(suiteName: "Inkpost.shortcut-tests.\(UUID())")!
    }

    @Test func defaultsToCommandQuoteAndPersistsChangeAndExplicitDisable() {
        let defaults = preferences()
        let registrar = Registrar()
        let controller = ShortcutController(defaults: defaults, registrar: registrar)
        #expect(controller.shortcut?.carbonKeyCode == kVK_ANSI_Quote)
        #expect(controller.shortcut?.modifiers == [.command])
        var wakes = 0
        controller.start { wakes += 1 }
        defer { controller.stop() }
        #expect(controller.isRegistered)
        registrar.action?()
        #expect(wakes == 1)
        let changed = KeyboardShortcuts.Shortcut(.m, modifiers: [.control, .option, .command])
        controller.save(changed)
        #expect(registrar.registered == changed)
        #expect(ShortcutController(defaults: defaults, registrar: Registrar()).shortcut == changed)
        controller.save(nil)
        #expect(registrar.registered == nil)
        #expect(!controller.isRegistered)
        #expect(ShortcutController(defaults: defaults, registrar: Registrar()).shortcut == nil)
    }

    @Test func failedRegistrationIsVisibleAndRetryAndStopWork() {
        let registrar = Registrar()
        registrar.fail = true
        let controller = ShortcutController(defaults: preferences(), registrar: registrar)
        controller.start {}
        #expect(!controller.isRegistered)
        #expect(controller.message?.contains("占用") == true)
        registrar.fail = false
        controller.retry()
        #expect(controller.isRegistered)
        #expect(controller.message == nil)
        controller.stop()
        #expect(registrar.registered == nil)
        #expect(!controller.isRegistered)
    }

    @Test func recorderSuspendsRegistrationAndResumesWithoutInvokingAction() {
        let registrar = Registrar()
        let controller = ShortcutController(defaults: preferences(), registrar: registrar)
        var wakes = 0
        controller.start { wakes += 1 }
        defer { controller.stop() }
        NotificationCenter.default.post(name: ShortcutController.recordingNotification, object: nil, userInfo: ["isActive": true])
        #expect(registrar.registered == nil)
        let changed = KeyboardShortcuts.Shortcut(.m, modifiers: [.control, .option, .command])
        controller.save(changed)
        #expect(!controller.isRegistered)
        NotificationCenter.default.post(name: ShortcutController.recordingNotification, object: nil, userInfo: ["isActive": false])
        #expect(registrar.registered == changed)
        #expect(wakes == 0)
    }

    @Test func damagedPreferencesDoNotSilentlyRestoreDefault() {
        let defaults = preferences()
        defaults.set(Data("broken".utf8), forKey: ShortcutController.storageKey)
        let controller = ShortcutController(defaults: defaults, registrar: Registrar())
        controller.start {}
        defer { controller.stop() }
        #expect(controller.shortcut == nil)
        #expect(controller.message?.contains("无法读取") == true)
        #expect(!controller.isRegistered)
    }

    @Test func realCarbonRegistrationRejectsDuplicateAndUnregisterReleasesIt() throws {
        _ = NSApplication.shared
        let shortcut = KeyboardShortcuts.Shortcut(.f18, modifiers: [.control, .option, .command])
        let first = GlobalHotKey(), second = GlobalHotKey()
        defer { first.unregister(); second.unregister() }
        try first.register(shortcut) {}
        #expect(throws: GlobalHotKey.RegistrationError.self) { try second.register(shortcut) {} }
        first.unregister()
        try second.register(shortcut) {}
    }

    @Test func togglingRetainsSameWindowDraftAndTaskInEveryPhase() {
        _ = NSApplication.shared
        let dispatch = DispatchController(service: DispatchService(), settings: DispatchSettings())
        let presentation = TaskPresentation()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 540),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        let bar = NativeMenuBar(controller: dispatch, presentation: presentation, openSettings: {}, window: window)
        let registrar = Registrar()
        let controller = ShortcutController(defaults: preferences(), registrar: registrar)
        controller.start { bar.toggleMainWindow() }
        defer { controller.stop(); bar.stop() }
        dispatch.state.title = "Keep title"
        dispatch.state.markdown = "Keep body\n\n  spaces"
        dispatch.state.taskID = UUID()
        let taskID = dispatch.state.taskID
        for phase in [TargetPhase.pending, .preparing, .needLogin, .awaitingConfirm, .failed, .cancelled] {
            dispatch.state.overallPhase = phase
            window.orderOut(nil)
            registrar.action?()
            #expect(window.isVisible)
            #expect(bar.mainWindow === window)
            #expect(dispatch.state.taskID == taskID)
            #expect(dispatch.state.overallPhase == phase)
            #expect(dispatch.state.title == "Keep title")
            #expect(dispatch.state.markdown == "Keep body\n\n  spaces")
            let focus = presentation.bodyFocusRequest
            let wasForeground = NSApp.isActive && window.isKeyWindow && window.isOnActiveSpace
            registrar.action?()
            #expect(window.isVisible == !wasForeground)
            #expect(dispatch.state.taskID == taskID)
            #expect(dispatch.state.overallPhase == phase)
            #expect(dispatch.state.markdown == "Keep body\n\n  spaces")
            if wasForeground { #expect(presentation.bodyFocusRequest == focus) }
        }
    }

    @Test func shortcutBringsCoveredWindowForwardInsteadOfHidingIt() {
        _ = NSApplication.shared
        let dispatch = DispatchController(service: DispatchService(), settings: DispatchSettings())
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 540),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        let other = NSWindow(contentRect: window.frame, styleMask: [.titled], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        let bar = NativeMenuBar(controller: dispatch, presentation: TaskPresentation(), openSettings: {}, window: window)
        defer { other.close(); bar.stop() }
        bar.showMainWindow()
        other.makeKeyAndOrderFront(nil)
        #expect(!window.isKeyWindow)
        bar.toggleMainWindow()
        #expect(window.isVisible)
        if NSApp.isActive { #expect(window.isKeyWindow) }
    }
}
