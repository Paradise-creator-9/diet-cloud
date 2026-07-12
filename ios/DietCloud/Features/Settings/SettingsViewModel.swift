import Foundation
import Observation

@MainActor
@Observable
final class SettingsViewModel {
    private(set) var errorMessage: String?
    private(set) var statusMessage: String?
    var isPresentingSignOutConfirm = false

    var draftCalories = ""
    var draftWeight = ""
    var draftProtein = ""
    var draftCarbs = ""
    var draftFiber = ""

    // MARK: Reminders

    private(set) var reminderSettings: ReminderSettings = .default
    private(set) var notificationAuthStatus: NotificationAuthStatus = .notDetermined
    private(set) var reminderStatusMessage: String?
    /// True when last apply failed and user can retry.
    private(set) var hasScheduleFailure = false

    let user: AuthUser
    private let goalsStore: GoalsStoring
    private let reminderSettingsStore: ReminderSettingsStoring
    private let notificationScheduler: NotificationScheduling
    private let onSignOut: () -> Void

    /// Bumps on every user mutation / refresh so stale async work cannot overwrite newer settings.
    private var mutationGeneration = 0
    /// Settings successfully applied to the scheduler (for reconcile dedupe).
    private var lastAppliedSettings: ReminderSettings?
    private var lastAppliedAuth: NotificationAuthStatus?
    private var timeApplyDebounceTask: Task<Void, Never>?
    /// Debounce for DatePicker continuous updates (milliseconds).
    private let timeApplyDebounceNanoseconds: UInt64 = 300_000_000

    init(
        user: AuthUser,
        goalsStore: GoalsStoring,
        reminderSettingsStore: ReminderSettingsStoring = InMemoryReminderSettingsStore(),
        notificationScheduler: NotificationScheduling,
        onSignOut: @escaping () -> Void
    ) {
        self.user = user
        self.goalsStore = goalsStore
        self.reminderSettingsStore = reminderSettingsStore
        self.notificationScheduler = notificationScheduler
        self.onSignOut = onSignOut
        loadDraftsFromStore()
        loadReminderSettingsFromStore()
    }

    func loadDraftsFromStore() {
        let g = goalsStore.goals
        draftCalories = Self.formatOptional(g.dailyCaloriesKcal)
        draftWeight = Self.formatOptional(g.targetWeightKg)
        draftProtein = Self.formatOptional(g.proteinGrams)
        draftCarbs = Self.formatOptional(g.carbsGrams)
        draftFiber = Self.formatOptional(g.fiberGrams)
        errorMessage = nil
        statusMessage = nil
    }

    func loadReminderSettingsFromStore() {
        reminderSettingsStore.reload()
        reminderSettings = reminderSettingsStore.settings
    }

    /// Refresh auth status; if schedulable, reconcile pending notifications to match local settings.
    /// Skips remove+add when settings and auth already match the last successful apply.
    func refreshNotificationAuthorizationAndReconcile() async {
        let generation = bumpGeneration()
        let status = await notificationScheduler.authorizationStatus()
        guard generation == mutationGeneration else { return }
        notificationAuthStatus = status

        guard status.canSchedule else {
            // denied / unsupported: never register; clear apply cache so a later grant re-applies.
            if status == .denied || status == .unsupported {
                lastAppliedSettings = nil
                lastAppliedAuth = status
            }
            return
        }

        await applySchedule(
            settings: reminderSettings,
            generation: generation,
            force: false
        )
    }

    /// Saves validated goals to local store. Empty fields clear that goal.
    @discardableResult
    func saveGoals() -> Bool {
        errorMessage = nil
        statusMessage = nil
        let (goals, message) = UserGoalsValidation.validate(
            caloriesText: draftCalories,
            weightText: draftWeight,
            proteinText: draftProtein,
            carbsText: draftCarbs,
            fiberText: draftFiber
        )
        if var goals {
            goals.fatGrams = goalsStore.goals.fatGrams
            goalsStore.save(goals)
            loadDraftsFromStore()
            statusMessage = "目标已保存到本机。"
            return true
        }
        errorMessage = message ?? "输入无效，请检查后重试。"
        return false
    }

    // MARK: - Reminder mutations

    func setReminderEnabled(_ kind: ReminderKind, enabled: Bool) async {
        reminderStatusMessage = nil
        errorMessage = nil
        hasScheduleFailure = false
        // Cancel pending time debounce so it cannot schedule stale times after a toggle.
        timeApplyDebounceTask?.cancel()
        timeApplyDebounceTask = nil

        let generation = bumpGeneration()

        if enabled {
            var status = await notificationScheduler.authorizationStatus()
            guard generation == mutationGeneration else { return }
            notificationAuthStatus = status

            if status == .notDetermined {
                status = await notificationScheduler.requestAuthorization()
                guard generation == mutationGeneration else { return }
                // Always re-read status after request (system is source of truth).
                status = await notificationScheduler.authorizationStatus()
                guard generation == mutationGeneration else { return }
                notificationAuthStatus = status
            }

            if !status.canSchedule {
                persistEnabled(kind, enabled: false)
                if status == .denied {
                    reminderStatusMessage = "通知未授权。请在系统设置中开启通知后重试。"
                } else {
                    reminderStatusMessage = "当前无法调度本地通知。"
                }
                return
            }

            persistEnabled(kind, enabled: true)
            await applySchedule(settings: reminderSettings, generation: generation, force: true)
        } else {
            persistEnabled(kind, enabled: false)
            await applySchedule(settings: reminderSettings, generation: generation, force: true)
        }
    }

    /// Saves time immediately; schedules apply after a short debounce (DatePicker scroll).
    func setReminderTime(_ kind: ReminderKind, date: Date) {
        reminderStatusMessage = nil
        // Keep UI + store on the latest minute immediately.
        var next = reminderSettings
        var item = next[kind]
        item.time = ReminderTime.from(date: date)
        next[kind] = item
        reminderSettings = next
        reminderSettingsStore.save(next)

        guard item.isEnabled else { return }

        let generation = bumpGeneration()
        timeApplyDebounceTask?.cancel()
        timeApplyDebounceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.timeApplyDebounceNanoseconds)
            guard !Task.isCancelled, generation == self.mutationGeneration else { return }
            var status = self.notificationAuthStatus
            if !status.canSchedule {
                status = await self.notificationScheduler.authorizationStatus()
                guard generation == self.mutationGeneration else { return }
                self.notificationAuthStatus = status
            }
            guard status.canSchedule else { return }
            await self.applySchedule(
                settings: self.reminderSettings,
                generation: generation,
                force: true
            )
        }
    }

    /// Waits for debounced time apply (tests / flush).
    func waitForPendingTimeApply() async {
        await timeApplyDebounceTask?.value
    }

    /// Retry scheduling after a failure using current settings.
    func retrySchedule() async {
        reminderStatusMessage = nil
        errorMessage = nil
        hasScheduleFailure = false
        let generation = bumpGeneration()
        let status = await notificationScheduler.authorizationStatus()
        guard generation == mutationGeneration else { return }
        notificationAuthStatus = status
        guard status.canSchedule else {
            if status == .denied {
                reminderStatusMessage = "通知未授权。请在系统设置中开启通知后重试。"
            }
            return
        }
        await applySchedule(settings: reminderSettings, generation: generation, force: true)
    }

    func bindingDate(for kind: ReminderKind) -> Date {
        reminderSettings[kind].time.date()
    }

    func requestSignOut() {
        isPresentingSignOutConfirm = true
    }

    func cancelSignOut() {
        isPresentingSignOutConfirm = false
    }

    func confirmSignOut() {
        isPresentingSignOutConfirm = false
        onSignOut()
    }

    // MARK: - Private

    @discardableResult
    private func bumpGeneration() -> Int {
        mutationGeneration += 1
        return mutationGeneration
    }

    private func persistEnabled(_ kind: ReminderKind, enabled: Bool) {
        var next = reminderSettings
        var item = next[kind]
        item.isEnabled = enabled
        next[kind] = item
        reminderSettings = next
        reminderSettingsStore.save(next)
    }

    private func applySchedule(
        settings: ReminderSettings,
        generation: Int,
        force: Bool
    ) async {
        guard generation == mutationGeneration else { return }

        if !force,
           let lastAppliedSettings,
           lastAppliedSettings == settings,
           lastAppliedAuth == notificationAuthStatus {
            return
        }

        do {
            try await notificationScheduler.apply(settings: settings)
            guard generation == mutationGeneration else { return }
            lastAppliedSettings = settings
            lastAppliedAuth = notificationAuthStatus
            hasScheduleFailure = false
            if errorMessage == "无法更新本地提醒，请稍后重试。" {
                errorMessage = nil
            }
        } catch {
            guard generation == mutationGeneration else { return }
            hasScheduleFailure = true
            errorMessage = "无法更新本地提醒，请稍后重试。"
            reminderStatusMessage = "提醒设置已保存到本机，但系统通知调度失败。"
            // Invalidate apply cache so next reconcile retries.
            lastAppliedSettings = nil
        }
    }

    private static func formatOptional(_ value: Double?) -> String {
        guard let value else { return "" }
        if value.rounded() == value { return String(Int(value)) }
        return String(format: "%.1f", value)
    }
}
