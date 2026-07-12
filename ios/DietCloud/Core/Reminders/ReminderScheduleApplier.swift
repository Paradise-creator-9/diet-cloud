import Foundation

/// Pure mapping from `ReminderSettings` to notification descriptors.
enum ReminderScheduleApplier {
    /// All Stage 12 stable identifiers (always removed before re-register).
    static var stableIdentifiers: [String] {
        ReminderKind.allStableIdentifiers
    }

    /// Descriptors for currently enabled reminders only.
    static func descriptors(from settings: ReminderSettings) -> [ReminderNotificationDescriptor] {
        ReminderKind.allCases.compactMap { kind in
            let item = settings[kind]
            guard item.isEnabled else { return nil }
            return ReminderNotificationDescriptor(
                identifier: kind.notificationIdentifier,
                title: kind.notificationTitle,
                body: kind.notificationBody,
                hour: item.time.hour,
                minute: item.time.minute,
                kind: kind
            )
        }
    }

    /// Bodies must stay generic (no health/diet metrics).
    static func bodiesLookSafe(_ descriptors: [ReminderNotificationDescriptor]) -> Bool {
        let banned = ["kcal", "kg", "体脂", "HealthKit", "健康数据", "步数"]
        for d in descriptors {
            let combined = d.title + d.body
            if banned.contains(where: { combined.localizedCaseInsensitiveContains($0) }) {
                return false
            }
        }
        return true
    }
}
