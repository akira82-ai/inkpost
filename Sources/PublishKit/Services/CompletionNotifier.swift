import Foundation
import UserNotifications

/// Notifications are optional; in-app status remains the source of truth.
@MainActor
public final class CompletionNotifier {
    public init() {}
    public func prepare() async {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        do { _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
        catch { NSLog("Inkpost notification authorization: %@", error.localizedDescription) }
    }
    nonisolated public static let taskIDKey = "inkpost.taskID"
    nonisolated public static let workspaceIDKey = "inkpost.workspaceID"

    public func deliver(_ message: String, title: String = "墨驿 Inkpost", taskID: UUID?, workspaceID: Int?) async {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let content = Self.content(message: message, title: title, taskID: taskID, workspaceID: workspaceID)
        do { try await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) }
        catch { NSLog("Inkpost notification delivery: %@", error.localizedDescription) }
    }
    static func content(message: String, title: String, taskID: UUID?, workspaceID: Int?) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title; content.body = message; content.sound = .default
        if let taskID { content.userInfo[Self.taskIDKey] = taskID.uuidString }
        if let workspaceID, workspaceID > 0 { content.userInfo[Self.workspaceIDKey] = workspaceID }
        return content
    }

}
