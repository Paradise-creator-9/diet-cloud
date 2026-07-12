import XCTest
@testable import DietCloud

@MainActor
final class ReminderScheduleTests: XCTestCase {
    private let user = AuthUser(id: "11111111-1111-1111-1111-111111111111", email: "a@example.com")

    func testDescriptorsOnlyEnabledAndSafeCopy() {
        var settings = ReminderSettings.default
        settings.breakfast.isEnabled = true
        settings.lunch.isEnabled = true
        let descriptors = ReminderScheduleApplier.descriptors(from: settings)
        XCTAssertEqual(descriptors.count, 2)
        XCTAssertEqual(Set(descriptors.map(\.identifier)), [
            "dietcloud.reminder.breakfast",
            "dietcloud.reminder.lunch"
        ])
        XCTAssertTrue(ReminderScheduleApplier.bodiesLookSafe(descriptors))
        for d in descriptors {
            XCTAssertFalse(d.body.contains("kcal"))
            XCTAssertFalse(d.body.contains("HealthKit"))
            XCTAssertFalse(d.title.contains("kg"))
        }
    }

    func testNotDeterminedFirstEnableRequestsOnceThenSchedules() async {
        let scheduler = MockNotificationScheduler(status: .notDetermined)
        scheduler.grantOnRequest = .authorized
        let store = InMemoryReminderSettingsStore()
        let vm = makeVM(store: store, scheduler: scheduler)

        await vm.setReminderEnabled(.breakfast, enabled: true)
        XCTAssertEqual(scheduler.requestAuthorizationCallCount, 1)
        XCTAssertTrue(vm.reminderSettings.breakfast.isEnabled)
        XCTAssertEqual(scheduler.scheduled.count, 1)

        await vm.setReminderEnabled(.lunch, enabled: true)
        XCTAssertEqual(scheduler.requestAuthorizationCallCount, 1, "should not request again")
        XCTAssertEqual(scheduler.scheduled.count, 2)
    }

    func testDeniedDoesNotScheduleAndRevertsToggle() async {
        let scheduler = MockNotificationScheduler(status: .denied)
        let store = InMemoryReminderSettingsStore()
        let vm = makeVM(store: store, scheduler: scheduler)

        await vm.setReminderEnabled(.dinner, enabled: true)
        XCTAssertEqual(scheduler.requestAuthorizationCallCount, 0)
        XCTAssertFalse(vm.reminderSettings.dinner.isEnabled)
        XCTAssertFalse(store.settings.dinner.isEnabled)
        XCTAssertTrue(scheduler.scheduled.isEmpty)
        XCTAssertNotNil(vm.reminderStatusMessage)
    }

    func testDeniedAfterRequestStillReverts() async {
        let scheduler = MockNotificationScheduler(status: .notDetermined)
        scheduler.grantOnRequest = .denied
        let vm = makeVM(scheduler: scheduler)
        await vm.setReminderEnabled(.weighIn, enabled: true)
        XCTAssertEqual(scheduler.requestAuthorizationCallCount, 1)
        XCTAssertFalse(vm.reminderSettings.weighIn.isEnabled)
        XCTAssertTrue(scheduler.scheduled.isEmpty)
    }

    func testDeniedDoesNotReconcileSchedule() async {
        let scheduler = MockNotificationScheduler(status: .denied)
        var settings = ReminderSettings.default
        settings.breakfast.isEnabled = true
        let store = InMemoryReminderSettingsStore(settings: settings)
        let vm = makeVM(store: store, scheduler: scheduler)
        await vm.refreshNotificationAuthorizationAndReconcile()
        XCTAssertTrue(scheduler.scheduled.isEmpty)
        XCTAssertEqual(scheduler.scheduleCallCount, 0)
    }

    func testAuthorizedEnablingThreeRegistersThree() async {
        let scheduler = MockNotificationScheduler(status: .authorized)
        let vm = makeVM(scheduler: scheduler)
        await vm.setReminderEnabled(.breakfast, enabled: true)
        await vm.setReminderEnabled(.lunch, enabled: true)
        await vm.setReminderEnabled(.dinner, enabled: true)
        XCTAssertEqual(scheduler.scheduled.count, 3)
    }

    func testProvisionalAllowsSchedule() async {
        let scheduler = MockNotificationScheduler(status: .provisional)
        let vm = makeVM(scheduler: scheduler)
        await vm.setReminderEnabled(.dailySummary, enabled: true)
        XCTAssertTrue(vm.reminderSettings.dailySummary.isEnabled)
        XCTAssertEqual(scheduler.scheduled.count, 1)
        XCTAssertEqual(vm.notificationAuthStatus, .provisional)
    }

    func testUnsupportedDoesNotSchedule() async {
        let scheduler = MockNotificationScheduler(status: .unsupported)
        let vm = makeVM(scheduler: scheduler)
        await vm.setReminderEnabled(.breakfast, enabled: true)
        XCTAssertFalse(vm.reminderSettings.breakfast.isEnabled)
        XCTAssertTrue(scheduler.scheduled.isEmpty)
        XCTAssertEqual(scheduler.requestAuthorizationCallCount, 0)
    }

    func testDisableRemovesCorrespondingId() async {
        let scheduler = MockNotificationScheduler(status: .authorized)
        let vm = makeVM(scheduler: scheduler)
        await vm.setReminderEnabled(.breakfast, enabled: true)
        await vm.setReminderEnabled(.lunch, enabled: true)
        await vm.setReminderEnabled(.breakfast, enabled: false)
        XCTAssertEqual(scheduler.scheduled.map(\.identifier), ["dietcloud.reminder.lunch"])
    }

    func testChangeTimeDebouncedToFinalValue() async {
        let scheduler = MockNotificationScheduler(status: .authorized)
        let vm = makeVM(scheduler: scheduler)
        await vm.setReminderEnabled(.lunch, enabled: true)
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: Date())
        comps.hour = 11
        comps.minute = 0
        comps.second = 0
        let first = cal.date(from: comps)!
        comps.hour = 13
        comps.minute = 45
        let second = cal.date(from: comps)!

        vm.setReminderTime(.lunch, date: first)
        vm.setReminderTime(.lunch, date: second)
        await vm.waitForPendingTimeApply()

        let d = scheduler.scheduledDescriptor(id: "dietcloud.reminder.lunch")
        XCTAssertEqual(d?.hour, 13)
        XCTAssertEqual(d?.minute, 45)
        XCTAssertEqual(vm.reminderSettings.lunch.time.hour, 13)
        XCTAssertEqual(vm.reminderSettings.lunch.time.minute, 45)
    }

    func testAllOffClearsStage12Pending() async {
        let scheduler = MockNotificationScheduler(status: .authorized)
        let vm = makeVM(scheduler: scheduler)
        await vm.setReminderEnabled(.breakfast, enabled: true)
        await vm.setReminderEnabled(.breakfast, enabled: false)
        XCTAssertTrue(scheduler.scheduled.isEmpty)
    }

    func testApplyDoesNotRemoveForeignNotifications() async {
        let scheduler = MockNotificationScheduler(status: .authorized)
        scheduler.seedForeignPending(["other.app.reminder"])
        try? await scheduler.apply(settings: .default)
        let pending = await scheduler.pendingIdentifiers()
        XCTAssertTrue(pending.contains("other.app.reminder"))
        XCTAssertEqual(Set(scheduler.lastRemovedIdentifiers), Set(ReminderKind.allStableIdentifiers))
    }

    func testReconcileDedupeSkipsRedundantApply() async {
        let scheduler = MockNotificationScheduler(status: .authorized)
        var settings = ReminderSettings.default
        settings.dinner.isEnabled = true
        let store = InMemoryReminderSettingsStore(settings: settings)
        let vm = makeVM(store: store, scheduler: scheduler)
        await vm.refreshNotificationAuthorizationAndReconcile()
        let firstScheduleCount = scheduler.scheduleCallCount
        XCTAssertGreaterThanOrEqual(firstScheduleCount, 1)
        await vm.refreshNotificationAuthorizationAndReconcile()
        XCTAssertEqual(scheduler.scheduleCallCount, firstScheduleCount, "second reconcile should dedupe")
    }

    func testRapidTogglesEndOnFinalState() async {
        let scheduler = MockNotificationScheduler(status: .authorized)
        let vm = makeVM(scheduler: scheduler)
        await vm.setReminderEnabled(.breakfast, enabled: true)
        await vm.setReminderEnabled(.breakfast, enabled: false)
        await vm.setReminderEnabled(.breakfast, enabled: true)
        XCTAssertTrue(vm.reminderSettings.breakfast.isEnabled)
        XCTAssertEqual(scheduler.scheduled.map(\.identifier), ["dietcloud.reminder.breakfast"])
    }

    func testScheduleFailureSurfacesErrorAndRetryWorks() async {
        let scheduler = MockNotificationScheduler(status: .authorized)
        scheduler.scheduleError = AppError.unknown(message: "add failed")
        let vm = makeVM(scheduler: scheduler)
        await vm.setReminderEnabled(.breakfast, enabled: true)
        // Settings still saved as enabled (user intent), but failure flagged.
        XCTAssertTrue(vm.reminderSettings.breakfast.isEnabled)
        XCTAssertTrue(vm.hasScheduleFailure)
        XCTAssertNotNil(vm.errorMessage)

        scheduler.scheduleError = nil
        // Clear in-memory scheduled from partial attempts
        await scheduler.removePendingNotificationRequests(withIdentifiers: ReminderKind.allStableIdentifiers)
        await vm.retrySchedule()
        XCTAssertFalse(vm.hasScheduleFailure)
        XCTAssertEqual(scheduler.scheduled.count, 1)
    }

    func testGoalsSaveUnaffectedByReminders() {
        let goals = InMemoryGoalsStore()
        let vm = makeVM(goals: goals, scheduler: MockNotificationScheduler(status: .authorized))
        vm.draftCalories = "2000"
        vm.draftProtein = "120"
        XCTAssertTrue(vm.saveGoals())
        XCTAssertEqual(goals.goals.dailyCaloriesKcal, 2000)
        XCTAssertEqual(goals.goals.proteinGrams, 120)
        XCTAssertFalse(vm.reminderSettings.anyEnabled)
    }

    func testMapAuthorizationStatuses() {
        XCTAssertEqual(SystemNotificationScheduler.map(.notDetermined), .notDetermined)
        XCTAssertEqual(SystemNotificationScheduler.map(.denied), .denied)
        XCTAssertEqual(SystemNotificationScheduler.map(.authorized), .authorized)
        XCTAssertEqual(SystemNotificationScheduler.map(.provisional), .provisional)
        XCTAssertEqual(SystemNotificationScheduler.map(.ephemeral), .unsupported)
    }

    // MARK: - Helpers

    private func makeVM(
        goals: GoalsStoring = InMemoryGoalsStore(),
        store: ReminderSettingsStoring = InMemoryReminderSettingsStore(),
        scheduler: MockNotificationScheduler
    ) -> SettingsViewModel {
        SettingsViewModel(
            user: user,
            goalsStore: goals,
            reminderSettingsStore: store,
            notificationScheduler: scheduler,
            onSignOut: {}
        )
    }
}
