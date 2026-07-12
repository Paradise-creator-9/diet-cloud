import XCTest
@testable import DietCloud

final class ReminderSettingsStoreTests: XCTestCase {
    func testDefaultAllDisabledWithExpectedTimes() {
        let settings = ReminderSettings.default
        XCTAssertFalse(settings.anyEnabled)
        XCTAssertEqual(settings.breakfast.time.hour, 8)
        XCTAssertEqual(settings.breakfast.time.minute, 0)
        XCTAssertEqual(settings.lunch.time.hour, 12)
        XCTAssertEqual(settings.lunch.time.minute, 30)
        XCTAssertEqual(settings.dinner.time.hour, 19)
        XCTAssertEqual(settings.dinner.time.minute, 0)
        XCTAssertEqual(settings.weighIn.time.hour, 7)
        XCTAssertEqual(settings.weighIn.time.minute, 30)
        XCTAssertEqual(settings.dailySummary.time.hour, 21)
        XCTAssertEqual(settings.dailySummary.time.minute, 30)
    }

    func testUserDefaultsRoundTrip() {
        let suite = "dietcloud.tests.reminders.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        var settings = ReminderSettings.default
        settings.breakfast.isEnabled = true
        settings.breakfast.time = ReminderTime(hour: 7, minute: 15)
        settings.dinner.isEnabled = true

        let store = UserDefaultsReminderSettingsStore(defaults: defaults)
        store.save(settings)

        let reloaded = UserDefaultsReminderSettingsStore(defaults: defaults)
        XCTAssertTrue(reloaded.settings.breakfast.isEnabled)
        XCTAssertEqual(reloaded.settings.breakfast.time.hour, 7)
        XCTAssertEqual(reloaded.settings.breakfast.time.minute, 15)
        XCTAssertTrue(reloaded.settings.dinner.isEnabled)
        XCTAssertFalse(reloaded.settings.lunch.isEnabled)
    }

    func testCorruptJSONFallsBackToDefault() {
        let suite = "dietcloud.tests.reminders.corrupt.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(Data("not-json".utf8), forKey: UserDefaultsReminderSettingsStore.storageKey)
        let store = UserDefaultsReminderSettingsStore(defaults: defaults)
        XCTAssertEqual(store.settings, .default)
        XCTAssertFalse(store.settings.anyEnabled)
    }

    func testStableIdentifiers() {
        XCTAssertEqual(ReminderKind.breakfast.notificationIdentifier, "dietcloud.reminder.breakfast")
        XCTAssertEqual(ReminderKind.lunch.notificationIdentifier, "dietcloud.reminder.lunch")
        XCTAssertEqual(ReminderKind.dinner.notificationIdentifier, "dietcloud.reminder.dinner")
        XCTAssertEqual(ReminderKind.weighIn.notificationIdentifier, "dietcloud.reminder.weighIn")
        XCTAssertEqual(ReminderKind.dailySummary.notificationIdentifier, "dietcloud.reminder.dailySummary")
        XCTAssertEqual(ReminderKind.allStableIdentifiers.count, 5)
    }
}
