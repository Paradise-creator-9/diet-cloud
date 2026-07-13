import Foundation

/// In-app navigation target after local reminder taps (Stage 17).
enum AppRoute: Equatable, Sendable {
    /// Open add-food sheet for the given meal on **today**.
    case addMeal(MealType)
    /// Open body metric sheet on **today**.
    case bodyMetric
    /// Ensure diary is on **today** (home).
    case homeToday
}

extension ReminderKind {
    /// Route used when the user taps this reminder notification.
    var appRoute: AppRoute {
        switch self {
        case .breakfast: return .addMeal(.breakfast)
        case .lunch: return .addMeal(.lunch)
        case .dinner: return .addMeal(.dinner)
        case .weighIn: return .bodyMetric
        case .dailySummary: return .homeToday
        }
    }
}

/// Keys / helpers for `UNNotificationContent.userInfo` (no secrets).
enum ReminderUserInfo {
    static let kindKey = "dietcloud.reminder.kind"

    static func make(kind: ReminderKind) -> [AnyHashable: Any] {
        [kindKey: kind.rawValue]
    }

    /// Resolve route from notification userInfo, falling back to request identifier.
    static func route(
        fromUserInfo userInfo: [AnyHashable: Any]?,
        identifier: String?
    ) -> AppRoute? {
        if let raw = userInfo?[kindKey] as? String,
           let kind = ReminderKind(rawValue: raw) {
            return kind.appRoute
        }
        if let identifier,
           let kind = ReminderKind.allCases.first(where: { $0.notificationIdentifier == identifier }) {
            return kind.appRoute
        }
        return nil
    }
}

/// Thread-safe pending route buffer for cold start / pre-login taps.
/// Consumed once after sign-in or when TodayMeals becomes active.
final class PendingDeepLinkStore: @unchecked Sendable {
    static let shared = PendingDeepLinkStore()

    static let didSetNotification = Notification.Name("dietcloud.pendingDeepLink.didSet")

    private let lock = NSLock()
    private var pending: AppRoute?

    private init() {}

    /// Overwrites any previous pending route (latest tap wins).
    func set(_ route: AppRoute) {
        lock.lock()
        pending = route
        lock.unlock()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didSetNotification, object: nil)
        }
    }

    /// Returns and clears the pending route, if any.
    func consume() -> AppRoute? {
        lock.lock()
        defer { lock.unlock() }
        let value = pending
        pending = nil
        return value
    }

    /// Test helper: peek without consuming.
    func peekForTests() -> AppRoute? {
        lock.lock(); defer { lock.unlock() }
        return pending
    }

    /// Test helper: clear without posting.
    func resetForTests() {
        lock.lock()
        pending = nil
        lock.unlock()
    }
}
