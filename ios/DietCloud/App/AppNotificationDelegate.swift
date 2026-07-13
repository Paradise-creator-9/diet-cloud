import Foundation
import UserNotifications

/// Handles local reminder taps (foreground / background / cold start).
/// Does **not** intercept Magic Link URLs — only notification responses.
final class AppNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = AppNotificationDelegate()

    private override init() {
        super.init()
    }

    /// Install as `UNUserNotificationCenter.current().delegate` as early as possible.
    func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    // Foreground presentation: still show banner so user can tap for routing.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // User tapped a notification (default action only — ignore dismiss / custom actions).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        // Swipe-away / clear must not navigate.
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else {
            return
        }
        let request = response.notification.request
        guard let route = ReminderUserInfo.route(
            fromUserInfo: request.content.userInfo,
            identifier: request.identifier
        ) else {
            return
        }
        PendingDeepLinkStore.shared.set(route)
    }
}
