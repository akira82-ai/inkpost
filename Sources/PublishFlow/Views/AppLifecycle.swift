import AppKit
import UserNotifications
import PublishKit

@MainActor
final class AppLifecycle: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var controller: DispatchController?
    private var pendingNotificationRoutes: [(UUID?, Int?)] = []
    private var menuBar: NativeMenuBar?
    private var updates: UpdateController?
    let shortcuts = ShortcutController()
    func configureUpdates(_ updates: UpdateController) { self.updates = updates }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if let updates, updates.state.installSessionActive, let reason = updates.blockingReason {
            updates.state.message = reason
            updates.state.isPresented = true
            showMainWindow()
            return .terminateCancel
        }
        return .terminateNow
    }
    func installMenuBar(controller: DispatchController, presentation: TaskPresentation, window: NSWindow, updates: UpdateController? = nil, openSettings: @escaping () -> Void) {
        guard menuBar == nil else { return }
        self.controller = controller
        let pending = pendingNotificationRoutes
        pendingNotificationRoutes = []
        Task { for (taskID, workspaceID) in pending { await self.openNotification(taskID: taskID, workspaceID: workspaceID) } }
        menuBar = NativeMenuBar(controller: controller, presentation: presentation, openSettings: openSettings, window: window, updates: updates)
        shortcuts.start { [weak self] in self?.menuBar?.toggleMainWindow() }
        showMainWindow()
        ApplicationStartup.instance?.whenReady(activate: { [weak self] in
            guard let self, let menuBar = self.menuBar else { return false }
            self.showMainWindow()
            return menuBar.mainWindow.isVisible
        }, stop: { NSApp.terminate(nil) })
    }
    func applicationWillTerminate(_ notification: Notification) {
        shortcuts.stop()
        ApplicationStartup.instance?.stopListening()
        menuBar?.stop()
    }
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Match LSUIElement before any window is shown, including unbundled development runs.
        NSApp.setActivationPolicy(.accessory)
        if Bundle.main.bundleURL.pathExtension == "app" { UNUserNotificationCenter.current().delegate = self }
    }
    func showMainWindow() { menuBar?.showMainWindow() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return false
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { completionHandler(); return }
        let info = response.notification.request.content.userInfo
        let taskID = (info[CompletionNotifier.taskIDKey] as? String).flatMap(UUID.init(uuidString:))
        let workspaceID = info[CompletionNotifier.workspaceIDKey] as? Int
        Task { @MainActor in
            await self.openNotification(taskID: taskID, workspaceID: workspaceID)
        }
        completionHandler()
    }
    private func openNotification(taskID: UUID?, workspaceID: Int?) async {
        guard let controller else {
            pendingNotificationRoutes.append((taskID, workspaceID))
            return
        }
        guard let taskID, let workspaceID, workspaceID > 0 else {
            controller.state.notice = "这条通知没有可打开的浏览器工作区，请查看任务状态"
            showMainWindow()
            return
        }
        await controller.openNotificationWorkspace(taskID: taskID, workspaceID: workspaceID)
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
