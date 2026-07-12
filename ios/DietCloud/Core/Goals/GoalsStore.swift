import Foundation

/// Local goals persistence (UserDefaults / in-memory for tests). No secrets.
protocol GoalsStoring: AnyObject, Sendable {
    var goals: UserGoals { get }
    func save(_ goals: UserGoals)
    func reload()
}

/// Thread-safe UserDefaults-backed goals store.
final class UserDefaultsGoalsStore: GoalsStoring, @unchecked Sendable {
    static let storageKey = "dietcloud.userGoals.v1"

    private let defaults: UserDefaults
    private let lock = NSLock()
    private var _goals: UserGoals

    var goals: UserGoals {
        lock.lock(); defer { lock.unlock() }
        return _goals
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self._goals = Self.load(from: defaults)
    }

    func save(_ goals: UserGoals) {
        lock.lock()
        _goals = goals
        lock.unlock()
        if let data = try? JSONEncoder().encode(goals) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    func reload() {
        let loaded = Self.load(from: defaults)
        lock.lock()
        _goals = loaded
        lock.unlock()
    }

    private static func load(from defaults: UserDefaults) -> UserGoals {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(UserGoals.self, from: data)
        else {
            return .empty
        }
        return decoded
    }
}

/// In-memory store for unit tests.
final class InMemoryGoalsStore: GoalsStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var _goals: UserGoals

    init(goals: UserGoals = .empty) {
        self._goals = goals
    }

    var goals: UserGoals {
        lock.lock(); defer { lock.unlock() }
        return _goals
    }

    func save(_ goals: UserGoals) {
        lock.lock()
        _goals = goals
        lock.unlock()
    }

    func reload() {}
}
