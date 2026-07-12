import Foundation

/// Local reminder settings persistence. No secrets / no cloud.
protocol ReminderSettingsStoring: AnyObject, Sendable {
    var settings: ReminderSettings { get }
    func save(_ settings: ReminderSettings)
    func reload()
}

final class UserDefaultsReminderSettingsStore: ReminderSettingsStoring, @unchecked Sendable {
    static let storageKey = "dietcloud.reminderSettings.v1"

    private let defaults: UserDefaults
    private let lock = NSLock()
    private var _settings: ReminderSettings

    var settings: ReminderSettings {
        lock.lock(); defer { lock.unlock() }
        return _settings
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self._settings = Self.load(from: defaults)
    }

    func save(_ settings: ReminderSettings) {
        lock.lock()
        _settings = settings
        lock.unlock()
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    func reload() {
        let loaded = Self.load(from: defaults)
        lock.lock()
        _settings = loaded
        lock.unlock()
    }

    private static func load(from defaults: UserDefaults) -> ReminderSettings {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(ReminderSettings.self, from: data)
        else {
            return .default
        }
        return decoded
    }
}

final class InMemoryReminderSettingsStore: ReminderSettingsStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var _settings: ReminderSettings

    init(settings: ReminderSettings = .default) {
        self._settings = settings
    }

    var settings: ReminderSettings {
        lock.lock(); defer { lock.unlock() }
        return _settings
    }

    func save(_ settings: ReminderSettings) {
        lock.lock()
        _settings = settings
        lock.unlock()
    }

    func reload() {}
}
