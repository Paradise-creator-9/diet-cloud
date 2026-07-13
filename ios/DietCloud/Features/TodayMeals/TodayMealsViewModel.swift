import Foundation
import Observation
import UIKit

enum TodayMealsLoadState: Equatable, Sendable {
    case loading
    case empty
    case loaded
    case error(String)
}

/// Add vs edit food form presented by the same sheet.
enum FoodFormMode: Equatable, Sendable {
    case add
    case edit
}

@MainActor
@Observable
final class TodayMealsViewModel {
    private(set) var loadState: TodayMealsLoadState = .loading
    private(set) var items: [FoodItem] = []
    private(set) var errorMessage: String?
    /// Non-error banner (e.g. saved to another date).
    private(set) var statusMessage: String?
    private(set) var isMutating = false

    /// Selected diary day (local start-of-day). Drives all fetch / write dateKeys.
    private(set) var selectedDate: Date

    /// Draft fields for add/edit form (bound from view).
    var draftName = ""
    var draftMeal: MealType = .breakfast
    var draftCalories = ""
    var draftProtein = ""
    var draftCarbs = ""
    var draftFat = ""
    var draftFiber = ""
    var draftGrams = ""
    var draftNote = ""
    /// Edit-mode date only (add mode still uses `selectedDateKey`).
    var draftDate: Date = Date()
    var isPresentingAddSheet = false
    private(set) var foodFormMode: FoodFormMode = .add
    /// Preserved across edit save — never write signed URLs to DB.
    private(set) var editingItemId: String?
    private(set) var editingPhotoPaths: [String] = []
    private(set) var editingSourceId: String?
    /// Read-only display URLs for edit sheet thumbnail (not persisted).
    private(set) var editingPhotoDisplayURLs: [String] = []

    var isEditingFood: Bool { foodFormMode == .edit }

    var foodFormNavigationTitle: String {
        isEditingFood ? "编辑食物" : "新增食物"
    }

    /// Optional JPEG-ready image chosen in the add/edit sheet (not a secret).
    private(set) var draftPhotoData: Data?
    private(set) var draftPhotoPreview: UIImage?
    private(set) var isPreparingPhoto = false
    /// Edit mode: user explicitly removed the meal photo (may replace multi-image with empty).
    private(set) var editPhotoRemoved = false
    /// Soft message when old Storage cleanup fails after a successful DB write.
    private(set) var photoCleanupWarning: String?

    /// AI analysis in progress (does not write DB).
    private(set) var isAnalyzing = false
    /// Short success summary after AI fill (not an error).
    private(set) var analysisSummary: String?

    // MARK: Body / activity / exercise (selectedDate)

    private(set) var bodyMetric: BodyMetric?
    private(set) var dailyActivity: DailyActivity?
    private(set) var exercises: [ExerciseActivity] = []

    var isPresentingBodySheet = false
    var isPresentingActivitySheet = false
    var isPresentingExerciseSheet = false

    var draftWeightKg = ""
    var draftBodyFatPercent = ""
    var draftBodyNote = ""
    // Stage 16 extended body drafts (optional metrics).
    var draftBmi = ""
    var draftMuscleKg = ""
    var draftBoneMassKg = ""
    var draftWaterPercent = ""
    var draftBmrKcal = ""
    var draftVisceralFat = ""
    /// Measured-at from AI (not shown as primary date control; save still uses selectedDateKey).
    var draftBodyMeasuredAt = ""

    /// Local body-scale screenshot JPEG (memory only — never Storage).
    private(set) var bodyDraftPhotoData: Data?
    private(set) var bodyDraftPhotoPreview: UIImage?
    private(set) var isPreparingBodyPhoto = false
    private(set) var isAnalyzingBody = false
    /// AI notes for display only (does not auto-overwrite draftBodyNote).
    private(set) var bodyAnalysisNotes: String?
    private(set) var bodyAnalysisConfidence: Double?
    /// When AI date differs from selectedDateKey.
    private(set) var bodyAnalysisDateHint: String?
    /// Last successful analysis (segment fields applied on save when present).
    private(set) var lastBodyAnalysis: BodyAnalysisResult?

    var canRunBodyAIAnalysis: Bool {
        bodyDraftPhotoData != nil && !isAnalyzingBody && !isPreparingBodyPhoto && !isMutating
    }

    var showBodyLowConfidenceWarning: Bool {
        guard let c = bodyAnalysisConfidence else { return false }
        return c < 0.5
    }

    var draftSteps = ""
    var draftActiveCalories = ""
    var draftDistanceKm = ""
    var draftActivityNote = ""

    var draftExerciseType = "骑行"
    var draftExerciseTitle = ""
    var draftExerciseDuration = ""
    var draftExerciseCalories = ""
    var draftExerciseDistance = ""
    var draftExerciseNote = ""

    // MARK: HealthKit import

    private(set) var isImportingHealthKit = false
    private(set) var healthKitStatusMessage: String?
    var isPresentingHealthKitOverwriteConfirm = false
    private var pendingHealthKitSnapshot: HealthKitDaySnapshot?

    let user: AuthUser

    private let foodRepository: FoodItemRepositoryProtocol
    private let photoRepository: MealPhotoRepositoryProtocol
    private let analyzeAPI: AnalyzeAPIClienting
    private let bodyRepository: BodyMetricsRepositoryProtocol
    private let dailyActivityRepository: DailyActivityRepositoryProtocol
    private let exerciseRepository: ExerciseActivityRepositoryProtocol
    private let healthKitClient: HealthKitClienting
    private let healthKitImporter: HealthKitImportServicing
    private let goalsStore: GoalsStoring
    private let favoriteFoodsStore: FavoriteFoodsStoring
    private let reminderSettingsStore: ReminderSettingsStoring
    private let notificationScheduler: NotificationScheduling
    private let diaryCalendar: DiaryCalendar
    /// Guards against out-of-order loads when the user flips dates quickly.
    private var loadGeneration = 0

    /// Local goals for day overview (reloaded when settings close).
    private(set) var goals: UserGoals = .empty

    /// Local favorite-food templates (UserDefaults; empty by default).
    private(set) var favoriteFoods: [FavoriteFood] = []

    var isPresentingFavoritesManageSheet = false
    /// `nil` = add template; non-nil = edit existing template id.
    private(set) var editingFavoriteId: String?
    var favoriteDraftName = ""
    var favoriteDraftMeal: MealType = .breakfast
    var favoriteDraftGrams = ""
    var favoriteDraftCalories = ""
    var favoriteDraftProtein = ""
    var favoriteDraftCarbs = ""
    var favoriteDraftFat = ""
    var favoriteDraftFiber = ""
    var favoriteDraftNote = ""
    private(set) var favoriteFormError: String?
    /// Non-error banner for favorites (quick-add / join).
    private(set) var favoriteStatusMessage: String?

    var goalsProgress: GoalsProgress {
        GoalsProgress(
            intakeKcal: dayEnergySummary.foodIntakeKcal,
            netKcal: dayEnergySummary.netKcal,
            proteinG: summary.protein,
            carbsG: summary.carbs,
            fiberG: summary.fiber,
            goals: goals
        )
    }

    /// Current diary day key (`YYYY-MM-DD`) for the selected date.
    var selectedDateKey: String {
        diaryCalendar.dateKey(from: selectedDate)
    }

    /// Alias for call sites / tests that still use `dateKey`.
    var dateKey: String { selectedDateKey }

    var isToday: Bool {
        diaryCalendar.isToday(selectedDateKey)
    }

    /// Chinese title for the selected day (今天 / 昨天 / 明天 / yyyy年M月d日).
    var displayTitle: String {
        diaryCalendar.displayTitle(forDateKey: selectedDateKey)
    }

    /// Navigation title: “今日饮食” on today, otherwise “饮食记录”.
    var navigationTitle: String {
        isToday ? "今日饮食" : "饮食记录"
    }

    var summary: DailyNutritionSummary {
        foodRepository.nutritionSummary(for: items)
    }

    /// Food + exercise + daily activity rollup for the **selected day only**.
    /// Refreshes whenever `items` / `dailyActivity` / `exercises` / `bodyMetric` update after load or mutation.
    ///
    /// **热量策略（方案 B）**：若当日 `daily_activities.source == healthkit`，
    /// 其 activeCalories 通常已含 workout 消耗，净热量只扣活动消耗，不重复扣运动列表。
    var dayEnergySummary: DayEnergySummary {
        let exerciseBurn = exercises.reduce(0.0) { $0 + $1.activeCalories }
        let activity = dailyActivity
        let weight: Double? = {
            guard let body = bodyMetric else { return nil }
            return body.weightKg
        }()
        return DayEnergySummary(
            foodIntakeKcal: summary.calories,
            exerciseBurnKcal: exerciseBurn,
            activityBurnKcal: activity?.activeCalories ?? 0,
            steps: activity?.steps ?? 0,
            weightKg: weight,
            dailyActivitySource: activity?.source
        )
    }

    /// All meal slots in Web display order (empty sections included when loaded).
    var mealSections: [MealGroup] {
        let key = selectedDateKey
        return MealType.displayOrder.map { meal in
            let filtered = items.filter { $0.meal == meal }
            return MealGroup(dateKey: key, meal: meal, items: filtered)
        }
    }

    /// True when user provided enough input for AI (hint and/or photo). Add mode only.
    var canRunAIAnalysis: Bool {
        guard !isEditingFood else { return false }
        let hasHint = !draftNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasPhoto = draftPhotoData != nil
        return (hasHint || hasPhoto) && !isAnalyzing && !isPreparingPhoto && !isMutating
    }

    init(
        user: AuthUser,
        foodRepository: FoodItemRepositoryProtocol,
        photoRepository: MealPhotoRepositoryProtocol,
        analyzeAPI: AnalyzeAPIClienting,
        bodyRepository: BodyMetricsRepositoryProtocol = MockBodyMetricsRepository(),
        dailyActivityRepository: DailyActivityRepositoryProtocol = MockDailyActivityRepository(),
        exerciseRepository: ExerciseActivityRepositoryProtocol = MockExerciseActivityRepository(),
        healthKitClient: HealthKitClienting = MockHealthKitClient(),
        healthKitImporter: HealthKitImportServicing? = nil,
        goalsStore: GoalsStoring = InMemoryGoalsStore(),
        favoriteFoodsStore: FavoriteFoodsStoring = InMemoryFavoriteFoodsStore(),
        reminderSettingsStore: ReminderSettingsStoring = InMemoryReminderSettingsStore(),
        notificationScheduler: NotificationScheduling = SystemNotificationScheduler(),
        diaryCalendar: DiaryCalendar = DiaryCalendar(),
        dateKey: String? = nil
    ) {
        self.user = user
        self.foodRepository = foodRepository
        self.photoRepository = photoRepository
        self.analyzeAPI = analyzeAPI
        self.bodyRepository = bodyRepository
        self.dailyActivityRepository = dailyActivityRepository
        self.exerciseRepository = exerciseRepository
        self.healthKitClient = healthKitClient
        self.healthKitImporter = healthKitImporter
            ?? HealthKitImportService(
                bodyRepository: bodyRepository,
                dailyRepository: dailyActivityRepository,
                exerciseRepository: exerciseRepository
            )
        self.goalsStore = goalsStore
        self.favoriteFoodsStore = favoriteFoodsStore
        self.reminderSettingsStore = reminderSettingsStore
        self.notificationScheduler = notificationScheduler
        self.diaryCalendar = diaryCalendar
        self.goals = goalsStore.goals
        self.favoriteFoods = favoriteFoodsStore.favorites
        if let dateKey, let parsed = diaryCalendar.date(fromDateKey: dateKey) {
            self.selectedDate = diaryCalendar.startOfDay(for: parsed)
        } else {
            self.selectedDate = diaryCalendar.startOfDay(for: Date())
        }
    }

    func reloadGoals() {
        goalsStore.reload()
        goals = goalsStore.goals
    }

    func reloadFavoriteFoods() {
        favoriteFoodsStore.reload()
        favoriteFoods = favoriteFoodsStore.favorites
    }

    func makeSettingsViewModel(onSignOut: @escaping () -> Void) -> SettingsViewModel {
        SettingsViewModel(
            user: user,
            goalsStore: goalsStore,
            reminderSettingsStore: reminderSettingsStore,
            notificationScheduler: notificationScheduler,
            onSignOut: onSignOut
        )
    }

    func makeTrendsViewModel() -> TrendsViewModel {
        TrendsViewModel(
            foodRepository: foodRepository,
            bodyRepository: bodyRepository,
            dailyActivityRepository: dailyActivityRepository,
            exerciseRepository: exerciseRepository,
            goalsStore: goalsStore,
            diaryCalendar: diaryCalendar
        )
    }

    func makePhotoLibraryViewModel() -> PhotoLibraryViewModel {
        PhotoLibraryViewModel(
            foodRepository: foodRepository,
            photoRepository: photoRepository,
            diaryCalendar: diaryCalendar
        )
    }

    var isHealthKitAvailable: Bool {
        healthKitClient.isAvailable
    }

    // MARK: - Date navigation

    func goToPreviousDay() async {
        let next = diaryCalendar.dateByAdding(days: -1, to: selectedDate)
        await selectDate(next)
    }

    func goToNextDay() async {
        let next = diaryCalendar.dateByAdding(days: 1, to: selectedDate)
        await selectDate(next)
    }

    func goToToday() async {
        await selectDate(diaryCalendar.startOfDay(for: Date()))
    }

    func selectDate(_ date: Date) async {
        prepareForDateChange()
        selectedDate = diaryCalendar.startOfDay(for: date)
        await load()
    }

    func selectDateKey(_ key: String) async {
        guard let date = diaryCalendar.date(fromDateKey: key) else {
            errorMessage = "日期无效。"
            return
        }
        await selectDate(date)
    }

    /// Closes sheets / AI work so date switches stay consistent.
    private func prepareForDateChange() {
        if isPresentingAddSheet { cancelAdd() }
        if isPresentingBodySheet { cancelBodySheet() }
        if isPresentingActivitySheet { cancelActivitySheet() }
        if isPresentingExerciseSheet { cancelExerciseSheet() }
        if isPresentingFavoritesManageSheet { closeFavoritesManageSheet() }
        isAnalyzing = false
        analysisSummary = nil
        favoriteStatusMessage = nil
    }

    // MARK: - Load

    func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        let key = selectedDateKey
        loadState = .loading
        errorMessage = nil
        do {
            async let foodTask = foodRepository.fetchByDateKey(key)
            async let bodyTask = bodyRepository.fetchByDateKey(key)
            async let dailyTask = dailyActivityRepository.fetchByDateKey(key)
            async let exerciseTask = exerciseRepository.fetchByDateKey(key)

            let fetched = try await foodTask
            let body = try await bodyTask
            let dailies = try await dailyTask
            let workouts = try await exerciseTask

            guard generation == loadGeneration else { return }
            items = fetched
            bodyMetric = body
            dailyActivity = Self.preferredDailyActivity(from: dailies)
            exercises = workouts
            loadState = fetched.isEmpty ? .empty : .loaded
        } catch {
            guard generation == loadGeneration else { return }
            let mapped = DataErrorMapping.map(error)
            errorMessage = mapped.userMessage
            loadState = .error(mapped.userMessage)
            items = []
            bodyMetric = nil
            dailyActivity = nil
            exercises = []
        }
    }

    /// Prefer manual source when multiple rows exist for a day.
    private static func preferredDailyActivity(from rows: [DailyActivity]) -> DailyActivity? {
        rows.first(where: { $0.source == "manual" }) ?? rows.first
    }

    // MARK: - Food form (add / edit)

    func openAddSheet(defaultMeal: MealType = .breakfast) {
        resetFoodFormDrafts()
        foodFormMode = .add
        editingItemId = nil
        editingPhotoPaths = []
        editingSourceId = nil
        editingPhotoDisplayURLs = []
        editPhotoRemoved = false
        draftMeal = defaultMeal
        draftDate = selectedDate
        clearDraftPhoto()
        errorMessage = nil
        statusMessage = nil
        photoCleanupWarning = nil
        analysisSummary = nil
        isPresentingAddSheet = true
    }

    func openEdit(_ item: FoodItem) {
        foodFormMode = .edit
        editingItemId = item.id
        editingPhotoPaths = item.photoPaths
        editingSourceId = item.sourceId
        editingPhotoDisplayURLs = item.photoURLs
        editPhotoRemoved = false
        draftName = item.name
        draftMeal = item.meal
        draftCalories = formatDraftNumber(item.calories)
        draftProtein = formatDraftNumber(item.protein)
        draftCarbs = formatDraftNumber(item.carbs)
        draftFat = formatDraftNumber(item.fat)
        draftFiber = formatDraftNumber(item.fiber)
        draftGrams = formatDraftNumber(item.grams)
        draftNote = item.note
        if let day = diaryCalendar.date(fromDateKey: item.dateKey) {
            draftDate = diaryCalendar.startOfDay(for: day)
        } else {
            draftDate = selectedDate
        }
        clearDraftPhoto()
        errorMessage = nil
        statusMessage = nil
        photoCleanupWarning = nil
        analysisSummary = nil
        isPresentingAddSheet = true
    }

    // MARK: - Reminder / deep-link routing (Stage 17)

    /// Apply a pending app route once (today + open the right sheet).
    func consumePendingRouteIfNeeded() async {
        guard let route = PendingDeepLinkStore.shared.consume() else { return }
        await applyRoute(route)
    }

    func applyRoute(_ route: AppRoute) async {
        // Always land on today for reminder-driven navigation.
        if !isToday {
            await goToToday()
        }
        switch route {
        case .addMeal(let meal):
            if isPresentingBodySheet { cancelBodySheet() }
            openAddSheet(defaultMeal: meal)
        case .bodyMetric:
            if isPresentingAddSheet { cancelAdd() }
            openBodySheet()
        case .homeToday:
            // Already on today; close stray sheets for a clean home.
            if isPresentingAddSheet { cancelAdd() }
            if isPresentingBodySheet { cancelBodySheet() }
        }
    }

    func cancelAdd() {
        isPresentingAddSheet = false
        clearFoodFormSession()
    }

    /// Called when the food sheet is dismissed (cancel, save success, or interactive dismiss).
    /// Ensures edit snapshots never leak into the next add session.
    func handleFoodFormDismissed() {
        // Binding may already have set isPresentingAddSheet = false.
        clearFoodFormSession()
    }

    private func clearFoodFormSession() {
        resetFoodFormDrafts()
        foodFormMode = .add
        editingItemId = nil
        editingPhotoPaths = []
        editingSourceId = nil
        editingPhotoDisplayURLs = []
        editPhotoRemoved = false
        clearDraftPhoto()
        // Keep errorMessage only while sheet is open; clear on dismiss.
        if !isPresentingAddSheet {
            errorMessage = nil
            analysisSummary = nil
        }
    }

    private func resetFoodFormDrafts() {
        draftName = ""
        draftCalories = ""
        draftProtein = ""
        draftCarbs = ""
        draftFat = ""
        draftFiber = ""
        draftGrams = ""
        draftNote = ""
        draftMeal = .breakfast
        draftDate = selectedDate
    }

    func clearDraftPhoto() {
        draftPhotoData = nil
        draftPhotoPreview = nil
    }

    func reportUserFacingError(_ message: String) {
        errorMessage = message
    }

    /// Compresses picker/camera data to JPEG before upload / AI (HEIC → JPEG).
    /// In edit mode, choosing a photo marks a **single-image replace** (replaces all existing paths).
    func setDraftPhoto(rawData: Data) async {
        isPreparingPhoto = true
        defer { isPreparingPhoto = false }
        do {
            let compressed = try ImageCompressor.compressToJPEG(data: rawData, preferredFileName: "meal.jpg")
            draftPhotoData = compressed.data
            draftPhotoPreview = UIImage(data: compressed.data)
            if isEditingFood {
                editPhotoRemoved = false
            }
            errorMessage = nil
        } catch {
            clearDraftPhoto()
            errorMessage = DataErrorMapping.map(error).userMessage
        }
    }

    /// Edit mode: remove meal photo(s) on next successful save (no Storage call until save).
    func markEditPhotoRemoved() {
        guard isEditingFood else { return }
        editPhotoRemoved = true
        clearDraftPhoto()
        errorMessage = nil
    }

    /// Clear a pending replace selection in edit mode (revert to original paths).
    func clearPendingEditPhotoReplace() {
        guard isEditingFood else { return }
        clearDraftPhoto()
        editPhotoRemoved = false
    }

    /// Whether edit form shows original storage photo (not replaced / not removed).
    var showsOriginalEditPhoto: Bool {
        isEditingFood && !editPhotoRemoved && draftPhotoData == nil && !editingPhotoPaths.isEmpty
    }

    /// Calls `/api/analyze-meal` and fills draft fields only — does **not** save.
    /// Add mode only; AI is date-agnostic; save still uses `selectedDateKey` for create.
    func runAIAnalysis() async {
        guard !isEditingFood else { return }
        errorMessage = nil
        analysisSummary = nil

        let hint = preferredAIHint()
        guard canRunAIAnalysis || (!hint.isEmpty || draftPhotoData != nil) else {
            errorMessage = "请先选择照片，或者至少写一句文字说明。"
            return
        }

        isAnalyzing = true
        defer { isAnalyzing = false }

        do {
            let request = try MealAnalysisRequest.make(
                hint: hint,
                jpegData: draftPhotoData,
                contentType: ImageCompressor.allowedContentType,
                fileName: "meal.jpg"
            )
            let result = try await analyzeAPI.analyzeMeal(request)
            applyAnalysisToDraft(result, userHint: hint)
        } catch {
            let mapped = mapAnalyzeError(error)
            errorMessage = mapped.userMessage
        }
    }

    /// Unified save for add (`create`) and edit (`update`). Prefer this over `saveNewItem`.
    func saveFoodItem() async {
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorMessage = "请填写食物名称。"
            return
        }

        let calories: Double
        let protein: Double
        let carbs: Double
        let fat: Double
        let fiber: Double
        let grams: Double
        do {
            calories = try parseNonNegativeField(draftCalories, name: "热量")
            protein = try parseNonNegativeField(draftProtein, name: "蛋白质")
            carbs = try parseNonNegativeField(draftCarbs, name: "碳水")
            fat = try parseNonNegativeField(draftFat, name: "脂肪")
            fiber = try parseNonNegativeField(draftFiber, name: "膳食纤维")
            grams = try parseNonNegativeField(draftGrams, name: "份量")
        } catch let message as FoodFormValidationMessage {
            errorMessage = message.text
            return
        } catch {
            errorMessage = "输入无效，请检查后重试。"
            return
        }

        guard !isMutating else { return }
        isMutating = true
        defer { isMutating = false }

        let writeDateKey: String
        switch foodFormMode {
        case .add:
            writeDateKey = selectedDateKey
        case .edit:
            writeDateKey = diaryCalendar.dateKey(from: draftDate)
        }

        var uploadedPathForRollback: String?
        do {
            let write: FoodItemWrite
            switch foodFormMode {
            case .add:
                var photoPaths: [String] = []
                if let photoData = draftPhotoData {
                    let uploaded = try await photoRepository.upload(
                        dateKey: writeDateKey,
                        fileName: "meal.jpg",
                        data: photoData,
                        contentType: ImageCompressor.allowedContentType
                    )
                    photoPaths = [uploaded.path]
                    uploadedPathForRollback = uploaded.path
                }
                write = FoodItemWrite(
                    dateKey: writeDateKey,
                    meal: draftMeal,
                    name: name,
                    grams: grams,
                    calories: calories,
                    protein: protein,
                    carbs: carbs,
                    fat: fat,
                    fiber: fiber,
                    note: draftNote.trimmingCharacters(in: .whitespacesAndNewlines),
                    photoPaths: photoPaths,
                    sourceId: nil
                )
                do {
                    _ = try await foodRepository.create(write)
                } catch {
                    if let path = uploadedPathForRollback {
                        try? await photoRepository.delete(paths: [path])
                    }
                    throw error
                }

            case .edit:
                guard let id = editingItemId else {
                    errorMessage = "无法保存：缺少记录标识。"
                    return
                }
                // Photo strategy (single primary image MVP):
                // - unchanged: keep all original paths (no upload)
                // - replace: upload one new path (replaces multi-image with single)
                // - remove: empty paths
                // Always write Storage paths, never signed URLs; always keep sourceId.
                let photoPaths: [String]
                if editPhotoRemoved {
                    photoPaths = []
                } else if let photoData = draftPhotoData {
                    let uploaded = try await photoRepository.upload(
                        dateKey: writeDateKey,
                        fileName: "meal.jpg",
                        data: photoData,
                        contentType: ImageCompressor.allowedContentType
                    )
                    photoPaths = [uploaded.path]
                    uploadedPathForRollback = uploaded.path
                } else {
                    photoPaths = editingPhotoPaths
                }
                write = FoodItemWrite(
                    dateKey: writeDateKey,
                    meal: draftMeal,
                    name: name,
                    grams: grams,
                    calories: calories,
                    protein: protein,
                    carbs: carbs,
                    fat: fat,
                    fiber: fiber,
                    note: draftNote.trimmingCharacters(in: .whitespacesAndNewlines),
                    photoPaths: photoPaths,
                    sourceId: editingSourceId
                )
                do {
                    _ = try await foodRepository.update(id: id, write: write)
                } catch {
                    if let path = uploadedPathForRollback {
                        try? await photoRepository.delete(paths: [path])
                    }
                    throw error
                }
            }

            let dateMovedAway = foodFormMode == .edit && writeDateKey != selectedDateKey
            let movedToKey = writeDateKey
            isPresentingAddSheet = false
            clearFoodFormSession()
            errorMessage = nil
            analysisSummary = nil
            photoCleanupWarning = nil
            if dateMovedAway {
                statusMessage = "已保存到 \(movedToKey)"
            } else {
                statusMessage = nil
            }
            await load()
        } catch {
            errorMessage = DataErrorMapping.map(error).userMessage
            // Keep sheet open; drafts and edit snapshot (photoPaths / sourceId) intact.
            // New upload already rolled back when create/update failed.
        }
    }

    /// Backward-compatible alias used by older call sites / tests.
    func saveNewItem() async {
        await saveFoodItem()
    }

    func deleteItem(_ item: FoodItem) async {
        guard !isMutating else { return }
        isMutating = true
        defer { isMutating = false }
        do {
            try await foodRepository.delete(id: item.id)
            errorMessage = nil
            await load()
        } catch {
            errorMessage = DataErrorMapping.map(error).userMessage
        }
    }

    // MARK: - Favorite foods (local templates → create only)

    /// Quick-add: create a diary row on **current** `selectedDateKey` using the template meal.
    /// Does not copy photos or sourceId; never updates existing food rows or templates.
    func quickAddFavorite(_ favorite: FavoriteFood) async {
        guard !isMutating else { return }
        let name = favorite.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorMessage = "请填写食物名称。"
            favoriteStatusMessage = nil
            return
        }
        // Defensive: reject non-finite / negative nutrition from hand-edited storage.
        let nutrients = [
            favorite.grams, favorite.calories, favorite.protein,
            favorite.carbs, favorite.fat, favorite.fiber,
        ]
        guard nutrients.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            errorMessage = "常吃模板数据无效，请在管理中重新编辑。"
            favoriteStatusMessage = nil
            return
        }

        isMutating = true
        defer { isMutating = false }

        var write = favorite.makeCreateWrite(dateKey: selectedDateKey)
        write.name = name
        // Explicit: never carry photos / identity from a prior diary row.
        write.photoPaths = []
        write.sourceId = nil
        do {
            _ = try await foodRepository.create(write)
            errorMessage = nil
            statusMessage = nil
            favoriteStatusMessage = "已添加「\(name)」"
            await load()
        } catch {
            errorMessage = DataErrorMapping.map(error).userMessage
            favoriteStatusMessage = nil
        }
    }

    /// Copy a diary food row into the local template list (no photos / sourceId).
    func addFoodItemToFavorites(_ item: FoodItem) {
        let template = FavoriteFood.fromFoodItem(item)
        var next = favoriteFoods
        next.append(template)
        favoriteFoodsStore.save(next)
        favoriteFoods = favoriteFoodsStore.favorites
        favoriteStatusMessage = "已加入常吃「\(template.name)」"
        errorMessage = nil
    }

    func openFavoritesManageSheet() {
        favoriteFormError = nil
        clearFavoriteDraft()
        isPresentingFavoritesManageSheet = true
    }

    func closeFavoritesManageSheet() {
        isPresentingFavoritesManageSheet = false
        favoriteFormError = nil
        clearFavoriteDraft()
    }

    func beginAddFavoriteTemplate() {
        clearFavoriteDraft()
        editingFavoriteId = nil
        favoriteFormError = nil
    }

    func beginEditFavoriteTemplate(_ favorite: FavoriteFood) {
        editingFavoriteId = favorite.id
        favoriteDraftName = favorite.name
        favoriteDraftMeal = favorite.meal
        favoriteDraftGrams = formatDraftNumber(favorite.grams)
        favoriteDraftCalories = formatDraftNumber(favorite.calories)
        favoriteDraftProtein = formatDraftNumber(favorite.protein)
        favoriteDraftCarbs = formatDraftNumber(favorite.carbs)
        favoriteDraftFat = formatDraftNumber(favorite.fat)
        favoriteDraftFiber = formatDraftNumber(favorite.fiber)
        favoriteDraftNote = favorite.note
        favoriteFormError = nil
    }

    /// Save add/edit of a **template only** — never touches diary food_items.
    @discardableResult
    func saveFavoriteTemplate() -> Bool {
        let (validated, message) = FavoriteFoodValidation.validate(
            id: editingFavoriteId,
            nameText: favoriteDraftName,
            meal: favoriteDraftMeal,
            gramsText: favoriteDraftGrams,
            caloriesText: favoriteDraftCalories,
            proteinText: favoriteDraftProtein,
            carbsText: favoriteDraftCarbs,
            fatText: favoriteDraftFat,
            fiberText: favoriteDraftFiber,
            noteText: favoriteDraftNote
        )
        guard let favorite = validated else {
            favoriteFormError = message ?? "输入无效，请检查后重试。"
            return false
        }

        var next = favoriteFoods
        if let id = editingFavoriteId, let index = next.firstIndex(where: { $0.id == id }) {
            next[index] = favorite
        } else {
            next.append(favorite)
        }
        favoriteFoodsStore.save(next)
        favoriteFoods = favoriteFoodsStore.favorites
        favoriteFormError = nil
        clearFavoriteDraft()
        return true
    }

    func deleteFavoriteTemplate(id: String) {
        var next = favoriteFoods
        next.removeAll { $0.id == id }
        favoriteFoodsStore.save(next)
        favoriteFoods = favoriteFoodsStore.favorites
        if editingFavoriteId == id {
            clearFavoriteDraft()
        }
    }

    private func clearFavoriteDraft() {
        editingFavoriteId = nil
        favoriteDraftName = ""
        favoriteDraftMeal = .breakfast
        favoriteDraftGrams = ""
        favoriteDraftCalories = ""
        favoriteDraftProtein = ""
        favoriteDraftCarbs = ""
        favoriteDraftFat = ""
        favoriteDraftFiber = ""
        favoriteDraftNote = ""
    }

    // MARK: - AI helpers

    private func preferredAIHint() -> String {
        let note = draftNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { return note }
        return draftName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func applyAnalysisToDraft(_ result: MealAnalysisResult, userHint: String) {
        let fill = MealAnalysisMapper.formFill(from: result, userHint: userHint)
        draftName = fill.name
        draftCalories = fill.calories
        draftProtein = fill.protein
        draftCarbs = fill.carbs
        draftFat = fill.fat
        draftFiber = formatDraftNumber(fill.fiber)
        draftGrams = fill.grams
        draftNote = fill.note
        analysisSummary = fill.summary
        errorMessage = nil
    }

    private struct FoodFormValidationMessage: Error {
        let text: String
    }

    /// Empty → 0; invalid / negative → error (does not call repository).
    /// Accepts `.` or `,` as decimal separator (not mixed thousands grouping).
    private func parseNonNegativeField(_ text: String, name: String) throws -> Double {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return 0 }
        let normalized: String
        if trimmed.contains(","), !trimmed.contains(".") {
            normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        } else {
            normalized = trimmed
        }
        guard let value = Double(normalized), value.isFinite else {
            throw FoodFormValidationMessage(text: "\(name)需为有效数字。")
        }
        if value < 0 {
            throw FoodFormValidationMessage(text: "\(name)不能为负数。")
        }
        return value
    }

    private func mapAnalyzeError(_ error: Error) -> AppError {
        AnalyzeAPIErrorMapping.map(error)
    }

    // MARK: - Body metrics

    func openBodySheet() {
        draftWeightKg = bodyMetric.map { formatDraftNumber($0.weightKg) } ?? ""
        draftBodyFatPercent = bodyMetric.map { formatDraftNumber($0.bodyFatPercent) } ?? ""
        draftBodyNote = bodyMetric?.note ?? ""
        draftBmi = bodyMetric.flatMap { $0.bmi > 0 ? formatDraftNumber($0.bmi) : nil } ?? ""
        draftMuscleKg = bodyMetric.flatMap { $0.muscleKg > 0 ? formatDraftNumber($0.muscleKg) : nil } ?? ""
        draftBoneMassKg = bodyMetric.flatMap { $0.boneMassKg > 0 ? formatDraftNumber($0.boneMassKg) : nil } ?? ""
        draftWaterPercent = bodyMetric.flatMap { $0.waterPercent > 0 ? formatDraftNumber($0.waterPercent) : nil } ?? ""
        draftBmrKcal = bodyMetric.flatMap { $0.bmrKcal > 0 ? formatDraftNumber($0.bmrKcal) : nil } ?? ""
        draftVisceralFat = bodyMetric.flatMap { $0.visceralFat > 0 ? formatDraftNumber($0.visceralFat) : nil } ?? ""
        draftBodyMeasuredAt = bodyMetric?.measuredAt ?? ""
        clearBodyAnalysisSession()
        errorMessage = nil
        isPresentingBodySheet = true
    }

    func cancelBodySheet() {
        isPresentingBodySheet = false
        clearBodyDraftFields()
        clearBodyAnalysisSession()
    }

    /// Compresses picker data for body AI only (never uploaded to Storage).
    func setBodyDraftPhoto(rawData: Data) async {
        isPreparingBodyPhoto = true
        defer { isPreparingBodyPhoto = false }
        do {
            let compressed = try ImageCompressor.compressToJPEG(
                data: rawData,
                preferredFileName: "body-scale.jpg"
            )
            bodyDraftPhotoData = compressed.data
            bodyDraftPhotoPreview = UIImage(data: compressed.data)
            errorMessage = nil
        } catch {
            clearBodyDraftPhoto()
            errorMessage = DataErrorMapping.map(error).userMessage
        }
    }

    func clearBodyDraftPhoto() {
        bodyDraftPhotoData = nil
        bodyDraftPhotoPreview = nil
    }

    /// Calls `/api/analyze-body` and fills draft fields only — does **not** upsert.
    func runBodyAIAnalysis() async {
        errorMessage = nil
        guard let photoData = bodyDraftPhotoData else {
            errorMessage = "请先选择身体数据截图。"
            return
        }
        guard !isAnalyzingBody else { return }

        isAnalyzingBody = true
        defer { isAnalyzingBody = false }

        do {
            let request = try BodyAnalysisRequest.make(
                jpegData: photoData,
                contentType: ImageCompressor.allowedContentType,
                fileName: "body-scale.jpg"
            )
            let result = try await analyzeAPI.analyzeBody(request)
            applyBodyAnalysisToDraft(result)
        } catch {
            errorMessage = mapAnalyzeError(error).userMessage
        }
    }

    private func applyBodyAnalysisToDraft(_ result: BodyAnalysisResult) {
        lastBodyAnalysis = result
        bodyAnalysisNotes = result.notes
        bodyAnalysisConfidence = result.confidence

        BodyAnalysisFormFill.applyIfPresent(
            BodyAnalysisFormFill.formatMetric(result.weightKg),
            onto: &draftWeightKg
        )
        BodyAnalysisFormFill.applyIfPresent(
            BodyAnalysisFormFill.formatMetric(result.bodyFatPercent),
            onto: &draftBodyFatPercent
        )
        BodyAnalysisFormFill.applyIfPresent(
            BodyAnalysisFormFill.formatMetric(result.bmi),
            onto: &draftBmi
        )
        BodyAnalysisFormFill.applyIfPresent(
            BodyAnalysisFormFill.formatMetric(result.muscleKg),
            onto: &draftMuscleKg
        )
        BodyAnalysisFormFill.applyIfPresent(
            BodyAnalysisFormFill.formatMetric(result.boneMassKg),
            onto: &draftBoneMassKg
        )
        BodyAnalysisFormFill.applyIfPresent(
            BodyAnalysisFormFill.formatMetric(result.waterPercent),
            onto: &draftWaterPercent
        )
        BodyAnalysisFormFill.applyIfPresent(
            BodyAnalysisFormFill.formatMetric(result.bmrKcal),
            onto: &draftBmrKcal
        )
        BodyAnalysisFormFill.applyIfPresent(
            BodyAnalysisFormFill.formatMetric(result.visceralFat),
            onto: &draftVisceralFat
        )
        if let measured = result.measuredAt, !measured.isEmpty {
            draftBodyMeasuredAt = measured
        }

        // Date mismatch: hint only — never change selectedDate.
        if let aiDate = result.date, !aiDate.isEmpty, aiDate != selectedDateKey {
            bodyAnalysisDateHint = "识别日期为 \(aiDate)，将保存到当前日 \(selectedDateKey)。"
        } else {
            bodyAnalysisDateHint = nil
        }
        // AI notes are display-only (do not overwrite draftBodyNote).
        errorMessage = nil
    }

    func saveBodyMetric() async {
        guard let weight = parseRequiredPositive(draftWeightKg) else {
            errorMessage = "请输入有效的体重（正数）。"
            return
        }

        let fat: Double
        let bmi: Double?
        let muscle: Double?
        let bone: Double?
        let water: Double?
        let bmr: Double?
        let visceral: Double?
        do {
            if let parsedFat = try parseOptionalPercentField(draftBodyFatPercent, name: "体脂率") {
                fat = parsedFat
            } else {
                fat = bodyMetric?.bodyFatPercent ?? 0
            }
            bmi = try parseOptionalNonNegative(draftBmi, name: "BMI")
            muscle = try parseOptionalNonNegative(draftMuscleKg, name: "肌肉量")
            bone = try parseOptionalNonNegative(draftBoneMassKg, name: "骨量")
            water = try parseOptionalPercentField(draftWaterPercent, name: "水分")
            bmr = try parseOptionalNonNegative(draftBmrKcal, name: "基础代谢")
            visceral = try parseOptionalNonNegative(draftVisceralFat, name: "内脏脂肪")
        } catch let message as FoodFormValidationMessage {
            errorMessage = message.text
            return
        } catch {
            errorMessage = "输入无效，请检查后重试。"
            return
        }

        guard !isMutating else { return }
        isMutating = true
        defer { isMutating = false }
        let key = selectedDateKey
        do {
            let write = BodyMetricWrite.formDraft(
                dateKey: key,
                weightKg: weight,
                bodyFatPercent: fat,
                bmi: bmi,
                muscleKg: muscle,
                boneMassKg: bone,
                waterPercent: water,
                bmrKcal: bmr,
                visceralFat: visceral,
                note: draftBodyNote.trimmingCharacters(in: .whitespacesAndNewlines),
                measuredAt: draftBodyMeasuredAt.isEmpty ? nil : draftBodyMeasuredAt,
                analysis: lastBodyAnalysis,
                existing: bodyMetric
            )
            _ = try await bodyRepository.upsert(write)
            isPresentingBodySheet = false
            errorMessage = nil
            clearBodyDraftFields()
            clearBodyAnalysisSession()
            await load()
        } catch {
            errorMessage = DataErrorMapping.map(error).userMessage
            // Keep drafts and screenshot so user can retry.
        }
    }

    private func clearBodyDraftFields() {
        draftWeightKg = ""
        draftBodyFatPercent = ""
        draftBodyNote = ""
        draftBmi = ""
        draftMuscleKg = ""
        draftBoneMassKg = ""
        draftWaterPercent = ""
        draftBmrKcal = ""
        draftVisceralFat = ""
        draftBodyMeasuredAt = ""
    }

    private func clearBodyAnalysisSession() {
        clearBodyDraftPhoto()
        isAnalyzingBody = false
        isPreparingBodyPhoto = false
        bodyAnalysisNotes = nil
        bodyAnalysisConfidence = nil
        bodyAnalysisDateHint = nil
        lastBodyAnalysis = nil
    }

    /// Called when body sheet is dismissed (cancel, save, or swipe). Drops screenshot from memory.
    func clearBodySessionAfterDismiss() {
        clearBodyAnalysisSession()
        // Draft text fields are reset on next openBodySheet; photo must not linger.
    }

    /// Empty → nil (caller keeps existing); invalid / out of 0...100 → error.
    private func parseOptionalPercentField(_ text: String, name: String) throws -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        guard let value = Double(trimmed.replacingOccurrences(of: ",", with: ".")), value.isFinite else {
            throw FoodFormValidationMessage(text: "\(name)需为有效数字。")
        }
        if value < 0 || value > 100 {
            throw FoodFormValidationMessage(text: "\(name)需在 0–100 之间。")
        }
        return value
    }

    /// Empty → nil (keep existing on write); invalid/negative → error.
    private func parseOptionalNonNegative(_ text: String, name: String) throws -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        guard let value = Double(trimmed.replacingOccurrences(of: ",", with: ".")), value.isFinite else {
            throw FoodFormValidationMessage(text: "\(name)需为有效数字。")
        }
        if value < 0 {
            throw FoodFormValidationMessage(text: "\(name)不能为负数。")
        }
        return value
    }

    func deleteBodyMetric() async {
        guard let id = bodyMetric?.id else { return }
        isMutating = true
        defer { isMutating = false }
        do {
            try await bodyRepository.delete(id: id)
            errorMessage = nil
            await load()
        } catch {
            errorMessage = DataErrorMapping.map(error).userMessage
        }
    }

    // MARK: - Daily activity

    func openActivitySheet() {
        draftSteps = dailyActivity.map { formatDraftNumber($0.steps) } ?? ""
        draftActiveCalories = dailyActivity.map { formatDraftNumber($0.activeCalories) } ?? ""
        draftDistanceKm = dailyActivity.map { formatDraftNumber($0.distanceKm) } ?? ""
        draftActivityNote = dailyActivity?.note ?? ""
        errorMessage = nil
        isPresentingActivitySheet = true
    }

    func cancelActivitySheet() {
        isPresentingActivitySheet = false
        draftSteps = ""
        draftActiveCalories = ""
        draftDistanceKm = ""
        draftActivityNote = ""
    }

    func saveDailyActivity() async {
        guard let steps = parseNonNegative(draftSteps) else {
            errorMessage = "步数需为大于等于 0 的数字。"
            return
        }
        guard let active = parseNonNegative(draftActiveCalories.isEmpty ? "0" : draftActiveCalories) else {
            errorMessage = "活动热量需为大于等于 0 的数字。"
            return
        }
        guard let distance = parseNonNegative(draftDistanceKm.isEmpty ? "0" : draftDistanceKm) else {
            errorMessage = "距离需为大于等于 0 的数字。"
            return
        }

        isMutating = true
        defer { isMutating = false }
        let key = selectedDateKey
        do {
            let write = DailyActivityWrite.manual(
                dateKey: key,
                steps: steps,
                activeCalories: active,
                distanceKm: distance,
                note: draftActivityNote,
                existing: dailyActivity
            )
            _ = try await dailyActivityRepository.upsert(write)
            isPresentingActivitySheet = false
            errorMessage = nil
            await load()
        } catch {
            errorMessage = DataErrorMapping.map(error).userMessage
        }
    }

    func deleteDailyActivity() async {
        guard let id = dailyActivity?.id else { return }
        isMutating = true
        defer { isMutating = false }
        do {
            try await dailyActivityRepository.delete(id: id)
            errorMessage = nil
            await load()
        } catch {
            errorMessage = DataErrorMapping.map(error).userMessage
        }
    }

    // MARK: - Exercise

    func openExerciseSheet() {
        draftExerciseType = "骑行"
        draftExerciseTitle = ""
        draftExerciseDuration = ""
        draftExerciseCalories = ""
        draftExerciseDistance = ""
        draftExerciseNote = ""
        errorMessage = nil
        isPresentingExerciseSheet = true
    }

    func cancelExerciseSheet() {
        isPresentingExerciseSheet = false
        draftExerciseType = "骑行"
        draftExerciseTitle = ""
        draftExerciseDuration = ""
        draftExerciseCalories = ""
        draftExerciseDistance = ""
        draftExerciseNote = ""
    }

    func saveExercise() async {
        guard let duration = parseRequiredPositive(draftExerciseDuration) else {
            errorMessage = "请输入有效的运动时长（分钟，正数）。"
            return
        }
        guard let calories = parseNonNegative(draftExerciseCalories.isEmpty ? "0" : draftExerciseCalories) else {
            errorMessage = "运动热量需为大于等于 0 的数字。"
            return
        }
        guard let distance = parseNonNegative(draftExerciseDistance.isEmpty ? "0" : draftExerciseDistance) else {
            errorMessage = "运动距离需为大于等于 0 的数字。"
            return
        }

        isMutating = true
        defer { isMutating = false }
        let key = selectedDateKey
        do {
            let write = ExerciseActivityWrite.manual(
                dateKey: key,
                type: draftExerciseType,
                title: draftExerciseTitle,
                durationMinutes: duration,
                activeCalories: calories,
                distanceKm: distance,
                note: draftExerciseNote
            )
            _ = try await exerciseRepository.create(write)
            isPresentingExerciseSheet = false
            errorMessage = nil
            await load()
        } catch {
            errorMessage = DataErrorMapping.map(error).userMessage
        }
    }

    func deleteExercise(_ exercise: ExerciseActivity) async {
        isMutating = true
        defer { isMutating = false }
        do {
            try await exerciseRepository.delete(id: exercise.id)
            errorMessage = nil
            await load()
        } catch {
            errorMessage = DataErrorMapping.map(error).userMessage
        }
    }

    // MARK: - HealthKit import

    /// Reads HealthKit for `selectedDateKey` and writes into app repositories.
    /// Does not write to HealthKit. Never silent-overwrite of manual body/daily.
    func importFromHealthKit(overwriteManual: Bool = false) async {
        healthKitStatusMessage = nil
        errorMessage = nil
        guard !isImportingHealthKit else { return }

        if !healthKitClient.isAvailable {
            healthKitStatusMessage = HealthKitError.unavailable.userMessage
            return
        }

        isImportingHealthKit = true
        defer { isImportingHealthKit = false }

        do {
            let status = healthKitClient.authorizationStatusSummary()
            if status == .denied {
                throw HealthKitError.authorizationDenied
            }
            if status == .notDetermined || status == .unavailable {
                // unavailable already handled; notDetermined → request
            }
            if status == .notDetermined {
                try await healthKitClient.requestReadAuthorization()
            }

            let key = selectedDateKey
            let snapshot = try await healthKitClient.fetchDay(dateKey: key, diaryCalendar: diaryCalendar)

            if !overwriteManual,
               HealthKitImportService.needsOverwriteConfirmation(
                   snapshot: snapshot,
                   existingBody: bodyMetric,
                   existingDaily: dailyActivity
               ) {
                pendingHealthKitSnapshot = snapshot
                isPresentingHealthKitOverwriteConfirm = true
                healthKitStatusMessage = "已有手动身体或每日活动记录。确认后将用健康数据更新这些项；运动记录会去重后追加。"
                return
            }

            let result = try await healthKitImporter.importDay(
                dateKey: key,
                snapshot: snapshot,
                existingBody: bodyMetric,
                existingDaily: dailyActivity,
                existingExercises: exercises,
                overwriteManual: overwriteManual
            )
            pendingHealthKitSnapshot = nil
            isPresentingHealthKitOverwriteConfirm = false
            healthKitStatusMessage = result.userMessage
            await load()
        } catch let hk as HealthKitError {
            healthKitStatusMessage = hk.userMessage
        } catch {
            healthKitStatusMessage = DataErrorMapping.map(error).userMessage
        }
    }

    func confirmHealthKitOverwriteImport() async {
        isPresentingHealthKitOverwriteConfirm = false
        guard let snapshot = pendingHealthKitSnapshot else {
            await importFromHealthKit(overwriteManual: true)
            return
        }
        isImportingHealthKit = true
        defer { isImportingHealthKit = false }
        do {
            let result = try await healthKitImporter.importDay(
                dateKey: selectedDateKey,
                snapshot: snapshot,
                existingBody: bodyMetric,
                existingDaily: dailyActivity,
                existingExercises: exercises,
                overwriteManual: true
            )
            pendingHealthKitSnapshot = nil
            healthKitStatusMessage = result.userMessage
            await load()
        } catch let hk as HealthKitError {
            healthKitStatusMessage = hk.userMessage
        } catch {
            healthKitStatusMessage = DataErrorMapping.map(error).userMessage
        }
    }

    func cancelHealthKitOverwriteImport() {
        isPresentingHealthKitOverwriteConfirm = false
        pendingHealthKitSnapshot = nil
        healthKitStatusMessage = "已取消覆盖。手动记录保持不变。"
    }

    // MARK: - Parsing

    private func parseNumber(_ text: String) -> Double {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Double(trimmed), value.isFinite, value >= 0 else {
            return 0
        }
        return value
    }

    private func parseNonNegative(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(trimmed), value.isFinite, value >= 0 else { return nil }
        return value
    }

    private func parseRequiredPositive(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        let normalized: String
        if trimmed.contains(","), !trimmed.contains(".") {
            normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        } else {
            normalized = trimmed
        }
        guard let value = Double(normalized), value.isFinite, value > 0 else { return nil }
        return value
    }

    private func formatDraftNumber(_ value: Double) -> String {
        if value == 0 { return "" }
        if value.rounded() == value { return String(Int(value)) }
        return String(format: "%.1f", value)
    }
}
