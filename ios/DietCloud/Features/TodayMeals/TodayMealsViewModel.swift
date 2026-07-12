import Foundation
import Observation
import UIKit

enum TodayMealsLoadState: Equatable, Sendable {
    case loading
    case empty
    case loaded
    case error(String)
}

@MainActor
@Observable
final class TodayMealsViewModel {
    private(set) var loadState: TodayMealsLoadState = .loading
    private(set) var items: [FoodItem] = []
    private(set) var errorMessage: String?
    private(set) var isMutating = false

    /// Selected diary day (local start-of-day). Drives all fetch / write dateKeys.
    private(set) var selectedDate: Date

    /// Draft fields for add form (bound from view).
    var draftName = ""
    var draftMeal: MealType = .breakfast
    var draftCalories = ""
    var draftProtein = ""
    var draftCarbs = ""
    var draftFat = ""
    var draftGrams = ""
    var draftNote = ""
    var isPresentingAddSheet = false

    /// Optional JPEG-ready image chosen in the add sheet (not a secret).
    private(set) var draftPhotoData: Data?
    private(set) var draftPhotoPreview: UIImage?
    private(set) var isPreparingPhoto = false

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

    let user: AuthUser

    private let foodRepository: FoodItemRepositoryProtocol
    private let photoRepository: MealPhotoRepositoryProtocol
    private let analyzeAPI: AnalyzeAPIClienting
    private let bodyRepository: BodyMetricsRepositoryProtocol
    private let dailyActivityRepository: DailyActivityRepositoryProtocol
    private let exerciseRepository: ExerciseActivityRepositoryProtocol
    private let diaryCalendar: DiaryCalendar
    /// Guards against out-of-order loads when the user flips dates quickly.
    private var loadGeneration = 0

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
            weightKg: weight
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

    /// True when user provided enough input for AI (hint and/or photo).
    var canRunAIAnalysis: Bool {
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
        self.diaryCalendar = diaryCalendar
        if let dateKey, let parsed = diaryCalendar.date(fromDateKey: dateKey) {
            self.selectedDate = diaryCalendar.startOfDay(for: parsed)
        } else {
            self.selectedDate = diaryCalendar.startOfDay(for: Date())
        }
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
        isAnalyzing = false
        analysisSummary = nil
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

    // MARK: - Add form

    func openAddSheet(defaultMeal: MealType = .breakfast) {
        draftMeal = defaultMeal
        draftName = ""
        draftCalories = ""
        draftProtein = ""
        draftCarbs = ""
        draftFat = ""
        draftGrams = ""
        draftNote = ""
        clearDraftPhoto()
        errorMessage = nil
        analysisSummary = nil
        isPresentingAddSheet = true
    }

    func cancelAdd() {
        isPresentingAddSheet = false
        draftName = ""
        draftCalories = ""
        draftProtein = ""
        draftCarbs = ""
        draftFat = ""
        draftGrams = ""
        draftNote = ""
        draftMeal = .breakfast
        clearDraftPhoto()
        errorMessage = nil
        analysisSummary = nil
    }

    func clearDraftPhoto() {
        draftPhotoData = nil
        draftPhotoPreview = nil
    }

    func reportUserFacingError(_ message: String) {
        errorMessage = message
    }

    /// Compresses picker data to JPEG before upload / AI (HEIC → JPEG).
    func setDraftPhoto(rawData: Data) async {
        isPreparingPhoto = true
        defer { isPreparingPhoto = false }
        do {
            let compressed = try ImageCompressor.compressToJPEG(data: rawData, preferredFileName: "meal.jpg")
            draftPhotoData = compressed.data
            draftPhotoPreview = UIImage(data: compressed.data)
            errorMessage = nil
        } catch {
            clearDraftPhoto()
            errorMessage = DataErrorMapping.map(error).userMessage
        }
    }

    /// Calls `/api/analyze-meal` and fills draft fields only — does **not** save.
    /// AI is date-agnostic; save still uses `selectedDateKey`.
    func runAIAnalysis() async {
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

    func saveNewItem() async {
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorMessage = "请填写食物名称。"
            return
        }

        isMutating = true
        defer { isMutating = false }

        let writeDateKey = selectedDateKey

        do {
            var photoPaths: [String] = []
            if let photoData = draftPhotoData {
                let uploaded = try await photoRepository.upload(
                    dateKey: writeDateKey,
                    fileName: "meal.jpg",
                    data: photoData,
                    contentType: ImageCompressor.allowedContentType
                )
                photoPaths = [uploaded.path]
            }

            let write = FoodItemWrite(
                dateKey: writeDateKey,
                meal: draftMeal,
                name: name,
                grams: parseNumber(draftGrams),
                calories: parseNumber(draftCalories),
                protein: parseNumber(draftProtein),
                carbs: parseNumber(draftCarbs),
                fat: parseNumber(draftFat),
                fiber: 0,
                note: draftNote.trimmingCharacters(in: .whitespacesAndNewlines),
                photoPaths: photoPaths
            )

            _ = try await foodRepository.create(write)
            isPresentingAddSheet = false
            clearDraftPhoto()
            errorMessage = nil
            analysisSummary = nil
            await load()
        } catch {
            errorMessage = DataErrorMapping.map(error).userMessage
        }
    }

    func deleteItem(_ item: FoodItem) async {
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
        draftGrams = fill.grams
        draftNote = fill.note
        analysisSummary = fill.summary
        errorMessage = nil
    }

    private func mapAnalyzeError(_ error: Error) -> AppError {
        AnalyzeAPIErrorMapping.map(error)
    }

    // MARK: - Body metrics

    func openBodySheet() {
        draftWeightKg = bodyMetric.map { formatDraftNumber($0.weightKg) } ?? ""
        draftBodyFatPercent = bodyMetric.map { formatDraftNumber($0.bodyFatPercent) } ?? ""
        draftBodyNote = bodyMetric?.note ?? ""
        errorMessage = nil
        isPresentingBodySheet = true
    }

    func cancelBodySheet() {
        isPresentingBodySheet = false
        draftWeightKg = ""
        draftBodyFatPercent = ""
        draftBodyNote = ""
    }

    func saveBodyMetric() async {
        guard let weight = parseRequiredPositive(draftWeightKg) else {
            errorMessage = "请输入有效的体重（正数）。"
            return
        }
        let fatText = draftBodyFatPercent.trimmingCharacters(in: .whitespacesAndNewlines)
        let fat: Double
        if fatText.isEmpty {
            fat = bodyMetric?.bodyFatPercent ?? 0
        } else if let value = Double(fatText), value.isFinite, value >= 0, value <= 100 {
            fat = value
        } else {
            errorMessage = "体脂率需在 0–100 之间。"
            return
        }

        isMutating = true
        defer { isMutating = false }
        let key = selectedDateKey
        do {
            let write = BodyMetricWrite.manual(
                dateKey: key,
                weightKg: weight,
                bodyFatPercent: fat,
                note: draftBodyNote,
                existing: bodyMetric
            )
            _ = try await bodyRepository.upsert(write)
            isPresentingBodySheet = false
            errorMessage = nil
            await load()
        } catch {
            errorMessage = DataErrorMapping.map(error).userMessage
        }
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
        guard let value = Double(trimmed), value.isFinite, value > 0 else { return nil }
        return value
    }

    private func formatDraftNumber(_ value: Double) -> String {
        if value == 0 { return "" }
        if value.rounded() == value { return String(Int(value)) }
        return String(format: "%.1f", value)
    }
}
