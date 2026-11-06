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
    public func deliver(_ message: String) async {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = "墨驿 Inkpost"; content.body = message; content.sound = .default
        do { try await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) }
        catch { NSLog("Inkpost notification delivery: %@", error.localizedDescription) }
    }
}
