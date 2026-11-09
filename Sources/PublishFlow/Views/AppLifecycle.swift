import AppKit
import UserNotifications
import PublishKit

@MainActor
final class AppLifecycle: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var controller: DispatchController?
    private var pendingNotificationRoutes: [(UUID?, Int?)] = []
    private var showWorkspace: (() -> Void)?
    private var menuBar: NativeMenuBar?
    func installMenuBar(controller: DispatchController, presentation: TaskPresentation, window: NSWindow, openWorkspace: @escaping () -> Void) {
        guard menuBar == nil else { return }
        self.controller = controller
        self.showWorkspace = { [weak self] in self?.menuBar?.showMainWindow() }
        let pending = pendingNotificationRoutes
        pendingNotificationRoutes = []
        Task { for (taskID, workspaceID) in pending { await self.openNotification(taskID: taskID, workspaceID: workspaceID) } }
        menuBar = NativeMenuBar(controller: controller, presentation: presentation, openWorkspace: openWorkspace, window: window)
        presentation.compactVisible = true
        presentation.compactFocusRequest = UUID()
    }
    func applicationWillTerminate(_ notification: Notification) { menuBar?.stop() }
    func applicationWillFinishLaunching(_ notification: Notification) {
        if Bundle.main.bundleURL.pathExtension == "app" { UNUserNotificationCenter.current().delegate = self }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
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
            showWorkspace?()
            return
        }
        await controller.openNotificationWorkspace(taskID: taskID, workspaceID: workspaceID)
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
