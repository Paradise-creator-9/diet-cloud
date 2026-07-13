import Foundation
import UserNotifications

/// Abstraction over `UNUserNotificationCenter` for testability.
protocol NotificationScheduling: AnyObject, Sendable {
    func authorizationStatus() async -> NotificationAuthStatus
    /// Requests alert + sound only (no badge). Returns mapped status after request.
    func requestAuthorization() async -> NotificationAuthStatus
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async
    func schedule(_ descriptors: [ReminderNotificationDescriptor]) async throws
    /// Pending identifiers currently registered (for tests / diagnostics).
    func pendingIdentifiers() async -> [String]
}

extension NotificationScheduling {
    /// Remove Stage 12 ids then schedule enabled descriptors.
    func apply(settings: ReminderSettings) async throws {
        await removePendingNotificationRequests(withIdentifiers: ReminderScheduleApplier.stableIdentifiers)
        let descriptors = ReminderScheduleApplier.descriptors(from: settings)
        try await schedule(descriptors)
    }
}

// MARK: - System

final class SystemNotificationScheduler: NotificationScheduling, @unchecked Sendable {
    private let center: UNUserNotificationCenter
    private let calendar: Calendar

    init(
        center: UNUserNotificationCenter = .current(),
        calendar: Calendar = .current
    ) {
        self.center = center
        self.calendar = calendar
    }

    func authorizationStatus() async -> NotificationAuthStatus {
        let settings = await center.notificationSettings()
        return Self.map(settings.authorizationStatus)
    }

    func requestAuthorization() async -> NotificationAuthStatus {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            // Always re-read system status after attempt (never trust local cache alone).
        }
        // Source of truth: re-query UNUserNotificationCenter after the request returns.
        return await authorizationStatus()
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func schedule(_ descriptors: [ReminderNotificationDescriptor]) async throws {
        for descriptor in descriptors {
            let content = UNMutableNotificationContent()
            content.title = descriptor.title
            content.body = descriptor.body
            content.sound = .default
            // Deep-link payload for Stage 17 (no secrets / no health metrics).
            content.userInfo = ReminderUserInfo.make(kind: descriptor.kind)

            var comps = DateComponents()
            comps.hour = descriptor.hour
            comps.minute = descriptor.minute
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: comps,
                repeats: true
            )
            let request = UNNotificationRequest(
                identifier: descriptor.identifier,
                content: content,
                trigger: trigger
            )
            try await center.add(request)
        }
    }

    func pendingIdentifiers() async -> [String] {
        let requests = await center.pendingNotificationRequests()
        return requests.map(\.identifier)
    }

    static func map(_ status: UNAuthorizationStatus) -> NotificationAuthStatus {
        switch status {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized: return .authorized
        case .provisional: return .provisional
        case .ephemeral: return .unsupported
        @unknown default: return .unsupported
        }
    }
}
