import Foundation
@testable import DietCloud

/// In-memory notification scheduler for unit tests only (not in the app target).
final class MockNotificationScheduler: NotificationScheduling, @unchecked Sendable {
    private let lock = NSLock()
    var status: NotificationAuthStatus = .notDetermined
    private(set) var requestAuthorizationCallCount = 0
    private(set) var scheduleCallCount = 0
    private(set) var removeCallCount = 0
    private(set) var lastRemovedIdentifiers: [String] = []
    private(set) var scheduled: [ReminderNotificationDescriptor] = []
    var scheduleError: Error?
    private var foreignPending: Set<String> = []
    var grantOnRequest: NotificationAuthStatus = .authorized

    init(status: NotificationAuthStatus = .notDetermined) {
        self.status = status
    }

    func seedForeignPending(_ ids: [String]) {
        lock.lock()
        foreignPending = Set(ids)
        lock.unlock()
    }

    func authorizationStatus() async -> NotificationAuthStatus {
        lock.lock(); defer { lock.unlock() }
        return status
    }

    func requestAuthorization() async -> NotificationAuthStatus {
        lock.lock()
        requestAuthorizationCallCount += 1
        if status == .notDetermined {
            status = grantOnRequest
        }
        let result = status
        lock.unlock()
        return result
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {
        lock.lock()
        removeCallCount += 1
        lastRemovedIdentifiers = identifiers
        let removeSet = Set(identifiers)
        scheduled.removeAll { removeSet.contains($0.identifier) }
        lock.unlock()
    }

    func schedule(_ descriptors: [ReminderNotificationDescriptor]) async throws {
        if let scheduleError { throw scheduleError }
        lock.lock()
        scheduleCallCount += 1
        for d in descriptors {
            scheduled.removeAll { $0.identifier == d.identifier }
            scheduled.append(d)
        }
        lock.unlock()
    }

    func pendingIdentifiers() async -> [String] {
        lock.lock(); defer { lock.unlock() }
        return scheduled.map(\.identifier) + Array(foreignPending)
    }

    func scheduledDescriptor(id: String) -> ReminderNotificationDescriptor? {
        lock.lock(); defer { lock.unlock() }
        return scheduled.first { $0.identifier == id }
    }
}
