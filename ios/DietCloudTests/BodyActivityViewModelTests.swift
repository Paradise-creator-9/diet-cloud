import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import DietCloud

@MainActor
final class BodyActivityViewModelTests: XCTestCase {
    private let user = AuthUser(id: "11111111-1111-1111-1111-111111111111", email: "a@example.com")

    private func makeVM(
        dateKey: String = "2026-07-13",
        body: MockBodyMetricsRepository? = nil,
        daily: MockDailyActivityRepository? = nil,
        exercise: MockExerciseActivityRepository? = nil,
        foodSeed: [FoodItem] = []
    ) -> (
        TodayMealsViewModel,
        MockBodyMetricsRepository,
        MockDailyActivityRepository,
        MockExerciseActivityRepository,
        MockFoodItemRepository
    ) {
        let photo = MockMealPhotoRepository(sessionUserId: user.id)
        let food = MockFoodItemRepository(sessionUserId: user.id, seed: foodSeed, photoRepository: photo)
        let bodyRepo = body ?? MockBodyMetricsRepository(sessionUserId: user.id)
        let dailyRepo = daily ?? MockDailyActivityRepository(sessionUserId: user.id)
        let exerciseRepo = exercise ?? MockExerciseActivityRepository(sessionUserId: user.id)
        let vm = TodayMealsViewModel(
            user: user,
            foodRepository: food,
            photoRepository: photo,
            analyzeAPI: MockAnalyzeAPIClient(),
            bodyRepository: bodyRepo,
            dailyActivityRepository: dailyRepo,
            exerciseRepository: exerciseRepo,
            dateKey: dateKey
        )
        return (vm, bodyRepo, dailyRepo, exerciseRepo, food)
    }

    func testDefaultLoadsBodyActivityExerciseForSelectedDate() async {
        let bodyRepo = MockBodyMetricsRepository(sessionUserId: user.id, seed: [
            makeBody(dateKey: "2026-07-13", weight: 76),
        ])
        let dailyRepo = MockDailyActivityRepository(sessionUserId: user.id, seed: [
            makeDaily(dateKey: "2026-07-13", steps: 8000),
        ])
        let exerciseRepo = MockExerciseActivityRepository(sessionUserId: user.id, seed: [
            makeExercise(dateKey: "2026-07-13", title: "Cycling", cal: 250),
        ])
        let (vm, body, daily, exercise, _) = makeVM(
            body: bodyRepo,
            daily: dailyRepo,
            exercise: exerciseRepo
        )
        await vm.load()
        XCTAssertEqual(body.lastFetchDateKey, "2026-07-13")
        XCTAssertEqual(daily.lastFetchDateKey, "2026-07-13")
        XCTAssertEqual(exercise.lastFetchDateKey, "2026-07-13")
        XCTAssertEqual(vm.bodyMetric?.weightKg, 76)
        XCTAssertEqual(vm.dailyActivity?.steps, 8000)
        XCTAssertEqual(vm.exercises.count, 1)
        XCTAssertEqual(vm.dayEnergySummary.exerciseBurnKcal, 250)
        XCTAssertEqual(vm.dayEnergySummary.steps, 8000)
    }

    func testSwitchToYesterdayFetchesYesterdayKeys() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let diary = DiaryCalendar(calendar: calendar)
        let today = diary.dateKey()
        let yesterday = diary.shiftingDateKey(today, byDays: -1)!
        let photo = MockMealPhotoRepository(sessionUserId: user.id)
        let body = MockBodyMetricsRepository(sessionUserId: user.id)
        let daily = MockDailyActivityRepository(sessionUserId: user.id)
        let exercise = MockExerciseActivityRepository(sessionUserId: user.id)
        let vm = TodayMealsViewModel(
            user: user,
            foodRepository: MockFoodItemRepository(sessionUserId: user.id, photoRepository: photo),
            photoRepository: photo,
            analyzeAPI: MockAnalyzeAPIClient(),
            bodyRepository: body,
            dailyActivityRepository: daily,
            exerciseRepository: exercise,
            diaryCalendar: diary,
            dateKey: today
        )
        await vm.goToPreviousDay()
        XCTAssertEqual(vm.selectedDateKey, yesterday)
        XCTAssertEqual(body.lastFetchDateKey, yesterday)
        XCTAssertEqual(daily.lastFetchDateKey, yesterday)
        XCTAssertEqual(exercise.lastFetchDateKey, yesterday)
    }

    func testBodySaveWritesSelectedDateKeyNotToday() async {
        let history = "2026-07-10"
        let (vm, body, _, _, _) = makeVM(dateKey: history)
        vm.openBodySheet()
        vm.draftWeightKg = "76.0"
        await vm.saveBodyMetric()
        XCTAssertEqual(body.lastUpsertDateKey, history)
        XCTAssertEqual(vm.bodyMetric?.dateKey, history)
        XCTAssertEqual(vm.bodyMetric?.weightKg, 76)
    }

    func testDailyActivitySaveWritesSelectedDateKey() async {
        let history = "2026-07-09"
        let (vm, _, daily, _, _) = makeVM(dateKey: history)
        vm.openActivitySheet()
        vm.draftSteps = "8000"
        vm.draftActiveCalories = "300"
        await vm.saveDailyActivity()
        XCTAssertEqual(daily.lastUpsertDateKey, history)
        XCTAssertEqual(vm.dailyActivity?.steps, 8000)
        XCTAssertEqual(vm.dailyActivity?.activeCalories, 300)
    }

    func testExerciseSaveWritesSelectedDateKey() async {
        let history = "2026-07-08"
        let (vm, _, _, exercise, _) = makeVM(dateKey: history)
        vm.openExerciseSheet()
        vm.draftExerciseType = "Cycling"
        vm.draftExerciseDuration = "30"
        vm.draftExerciseCalories = "250"
        await vm.saveExercise()
        XCTAssertEqual(exercise.lastCreateDateKey, history)
        XCTAssertEqual(vm.exercises.count, 1)
        XCTAssertEqual(vm.exercises.first?.dateKey, history)
        XCTAssertEqual(vm.exercises.first?.activeCalories, 250)
    }

    func testInvalidWeightDoesNotSave() async {
        let (vm, body, _, _, _) = makeVM()
        vm.openBodySheet()
        vm.draftWeightKg = "0"
        await vm.saveBodyMetric()
        XCTAssertNil(body.lastUpsertDateKey)
        XCTAssertEqual(vm.errorMessage, "请输入有效的体重（正数）。")
        XCTAssertTrue(vm.isPresentingBodySheet)
    }

    func testInvalidBodyFatDoesNotSave() async {
        let (vm, body, _, _, _) = makeVM()
        vm.openBodySheet()
        vm.draftWeightKg = "70"
        vm.draftBodyFatPercent = "150"
        await vm.saveBodyMetric()
        XCTAssertNil(body.lastUpsertDateKey)
        XCTAssertEqual(vm.errorMessage, "体脂率需在 0–100 之间。")
    }

    func testInvalidStepsDoesNotSave() async {
        let (vm, _, daily, _, _) = makeVM()
        vm.openActivitySheet()
        vm.draftSteps = "-1"
        await vm.saveDailyActivity()
        XCTAssertNil(daily.lastUpsertDateKey)
        XCTAssertNotNil(vm.errorMessage)
    }

    func testInvalidExerciseDurationDoesNotSave() async {
        let (vm, _, _, exercise, _) = makeVM()
        vm.openExerciseSheet()
        vm.draftExerciseDuration = "0"
        vm.draftExerciseCalories = "100"
        await vm.saveExercise()
        XCTAssertNil(exercise.lastCreateDateKey)
        XCTAssertEqual(vm.errorMessage, "请输入有效的运动时长（分钟，正数）。")
    }

    func testDeleteExerciseRefreshesList() async {
        let seed = makeExercise(dateKey: "2026-07-13", title: "Run", cal: 100)
        let exerciseRepo = MockExerciseActivityRepository(sessionUserId: user.id, seed: [seed])
        let (vm, _, _, _, _) = makeVM(exercise: exerciseRepo)
        await vm.load()
        XCTAssertEqual(vm.exercises.count, 1)
        await vm.deleteExercise(seed)
        XCTAssertTrue(vm.exercises.isEmpty)
    }

    func testDeleteBodyAndActivity() async {
        let bodyRepo = MockBodyMetricsRepository(sessionUserId: user.id, seed: [
            makeBody(dateKey: "2026-07-13", weight: 70),
        ])
        let dailyRepo = MockDailyActivityRepository(sessionUserId: user.id, seed: [
            makeDaily(dateKey: "2026-07-13", steps: 1000),
        ])
        let (vm, _, _, _, _) = makeVM(body: bodyRepo, daily: dailyRepo)
        await vm.load()
        XCTAssertNotNil(vm.bodyMetric)
        XCTAssertNotNil(vm.dailyActivity)
        await vm.deleteBodyMetric()
        XCTAssertNil(vm.bodyMetric)
        // Daily still present after body delete (load refreshes both)
        XCTAssertNotNil(vm.dailyActivity)
        await vm.deleteDailyActivity()
        XCTAssertNil(vm.dailyActivity)
    }

    func testEnergySummaryOnlyUsesSelectedDate() async {
        let food = FoodItem(
            id: "f1",
            dateKey: "2026-07-13",
            meal: .lunch,
            name: "饭",
            grams: 0,
            calories: 500,
            protein: 0,
            carbs: 0,
            fat: 0,
            fiber: 0,
            note: "",
            photoPaths: [],
            photoURLs: [],
            createdAt: "2026-07-13T08:00:00Z",
            sourceId: nil
        )
        let bodyRepo = MockBodyMetricsRepository(sessionUserId: user.id, seed: [
            makeBody(dateKey: "2026-07-13", weight: 76),
            makeBody(dateKey: "2026-07-12", weight: 99),
        ])
        let dailyRepo = MockDailyActivityRepository(sessionUserId: user.id, seed: [
            makeDaily(dateKey: "2026-07-13", steps: 8000, active: 200),
            makeDaily(dateKey: "2026-07-12", steps: 1, active: 999),
        ])
        let exerciseRepo = MockExerciseActivityRepository(sessionUserId: user.id, seed: [
            makeExercise(dateKey: "2026-07-13", title: "Bike", cal: 250),
            makeExercise(dateKey: "2026-07-12", title: "Other", cal: 900),
        ])
        let (vm, _, _, _, _) = makeVM(
            body: bodyRepo,
            daily: dailyRepo,
            exercise: exerciseRepo,
            foodSeed: [food]
        )
        await vm.load()
        XCTAssertEqual(vm.dayEnergySummary.foodIntakeKcal, 500)
        XCTAssertEqual(vm.dayEnergySummary.exerciseBurnKcal, 250)
        XCTAssertEqual(vm.dayEnergySummary.activityBurnKcal, 200)
        XCTAssertEqual(vm.dayEnergySummary.netKcal, 50) // 500 - 200 - 250
        XCTAssertEqual(vm.dayEnergySummary.weightKg, 76)
        XCTAssertEqual(vm.dayEnergySummary.steps, 8000)
    }

    func testEnergySummaryZeroWhenNoData() async {
        let (vm, _, _, _, _) = makeVM(dateKey: "2026-07-13")
        await vm.load()
        XCTAssertEqual(vm.dayEnergySummary, .zero)
        XCTAssertEqual(vm.dayEnergySummary.netKcal, 0)
        XCTAssertNil(vm.dayEnergySummary.weightKg)
    }

    func testEnergySummaryRefreshesAfterDeleteActivityAndExercise() async {
        let dailyRepo = MockDailyActivityRepository(sessionUserId: user.id, seed: [
            makeDaily(dateKey: "2026-07-13", steps: 1000, active: 300),
        ])
        let exerciseSeed = makeExercise(dateKey: "2026-07-13", title: "Bike", cal: 250)
        let exerciseRepo = MockExerciseActivityRepository(sessionUserId: user.id, seed: [exerciseSeed])
        let (vm, _, _, _, _) = makeVM(daily: dailyRepo, exercise: exerciseRepo)
        await vm.load()
        XCTAssertEqual(vm.dayEnergySummary.activityBurnKcal, 300)
        XCTAssertEqual(vm.dayEnergySummary.exerciseBurnKcal, 250)
        XCTAssertEqual(vm.dayEnergySummary.netKcal, -550)

        await vm.deleteExercise(exerciseSeed)
        XCTAssertEqual(vm.dayEnergySummary.exerciseBurnKcal, 0)
        XCTAssertEqual(vm.dayEnergySummary.activityBurnKcal, 300)
        XCTAssertEqual(vm.dayEnergySummary.netKcal, -300)

        await vm.deleteDailyActivity()
        XCTAssertEqual(vm.dayEnergySummary.activityBurnKcal, 0)
        XCTAssertEqual(vm.dayEnergySummary.steps, 0)
        XCTAssertEqual(vm.dayEnergySummary.netKcal, 0)
    }

    func testEnergySummaryDoesNotMixOtherDateAfterSwitch() async {
        let dailyRepo = MockDailyActivityRepository(sessionUserId: user.id, seed: [
            makeDaily(dateKey: "2026-07-13", steps: 8000, active: 200),
            makeDaily(dateKey: "2026-07-12", steps: 1, active: 999),
        ])
        let exerciseRepo = MockExerciseActivityRepository(sessionUserId: user.id, seed: [
            makeExercise(dateKey: "2026-07-13", title: "Today", cal: 100),
            makeExercise(dateKey: "2026-07-12", title: "Yest", cal: 900),
        ])
        let (vm, _, _, _, _) = makeVM(
            dateKey: "2026-07-13",
            daily: dailyRepo,
            exercise: exerciseRepo
        )
        await vm.load()
        XCTAssertEqual(vm.dayEnergySummary.activityBurnKcal, 200)
        XCTAssertEqual(vm.dayEnergySummary.exerciseBurnKcal, 100)

        await vm.selectDateKey("2026-07-12")
        XCTAssertEqual(vm.dayEnergySummary.activityBurnKcal, 999)
        XCTAssertEqual(vm.dayEnergySummary.exerciseBurnKcal, 900)
        XCTAssertEqual(vm.dayEnergySummary.steps, 1)
        XCTAssertFalse((vm.errorMessage ?? "").contains("eyJ"))
        XCTAssertFalse(vm.selectedDateKey.contains(user.id))
    }

    func testRepositoryErrorDoesNotLeakToken() async {
        let body = MockBodyMetricsRepository(sessionUserId: user.id)
        body.forcedError = AppError.auth(.provider(message: "bad eyJhbGciOiJIUzI1NiJ9.payload.sig"))
        let (vm, _, _, _, _) = makeVM(body: body)
        await vm.load()
        if case .error(let message) = vm.loadState {
            XCTAssertFalse(message.contains("eyJ"))
            XCTAssertFalse(message.contains(user.id))
        } else {
            XCTFail("expected error state")
        }
    }

    func testDateSwitchEmptyBodyActivity() async {
        let bodyRepo = MockBodyMetricsRepository(sessionUserId: user.id, seed: [
            makeBody(dateKey: "2026-07-10", weight: 70),
        ])
        let (vm, _, _, _, _) = makeVM(dateKey: "2026-07-13", body: bodyRepo)
        await vm.load()
        XCTAssertNil(vm.bodyMetric)
        await vm.selectDateKey("2026-07-10")
        XCTAssertEqual(vm.bodyMetric?.weightKg, 70)
        await vm.selectDateKey("2026-07-11")
        XCTAssertNil(vm.bodyMetric)
    }

    // MARK: - Body screenshot AI (Stage 16)

    private func makeVMWithAnalyze(
        dateKey: String = "2026-07-13",
        body: MockBodyMetricsRepository? = nil,
        analyze: MockAnalyzeAPIClient
    ) -> (TodayMealsViewModel, MockBodyMetricsRepository, MockMealPhotoRepository, MockAnalyzeAPIClient) {
        let photo = MockMealPhotoRepository(sessionUserId: user.id)
        let food = MockFoodItemRepository(sessionUserId: user.id, photoRepository: photo)
        let bodyRepo = body ?? MockBodyMetricsRepository(sessionUserId: user.id)
        let vm = TodayMealsViewModel(
            user: user,
            foodRepository: food,
            photoRepository: photo,
            analyzeAPI: analyze,
            bodyRepository: bodyRepo,
            dailyActivityRepository: MockDailyActivityRepository(sessionUserId: user.id),
            exerciseRepository: MockExerciseActivityRepository(sessionUserId: user.id),
            dateKey: dateKey
        )
        return (vm, bodyRepo, photo, analyze)
    }

    private func sampleBodyAnalysis(
        confidence: Double = 0.9,
        date: String? = "2026-07-13",
        weight: Double? = 72.5,
        fat: Double? = 18.2,
        bmi: Double? = 22.1,
        muscle: Double? = 50,
        bone: Double? = 2.8,
        water: Double? = 55,
        bmr: Double? = 1480,
        visceral: Double? = 7,
        notes: String = "请核对"
    ) -> BodyAnalysisResult {
        BodyAnalysisResult(
            confidence: confidence,
            date: date,
            measuredAt: date.map { "\($0)T07:30" },
            score: nil,
            weightKg: weight,
            bmi: bmi,
            bodyFatPercent: fat,
            bodyAge: nil,
            bodyType: nil,
            muscleKg: muscle,
            skeletalMuscleKg: nil,
            boneMassKg: bone,
            waterPercent: water,
            visceralFat: visceral,
            bmrKcal: bmr,
            proteinPercent: nil,
            trunkFatPercent: nil,
            trunkMuscleKg: nil,
            leftArmFatPercent: nil,
            leftArmMuscleKg: nil,
            rightArmFatPercent: nil,
            rightArmMuscleKg: nil,
            leftLegFatPercent: nil,
            leftLegMuscleKg: nil,
            rightLegFatPercent: nil,
            rightLegMuscleKg: nil,
            notes: notes,
            model: "mock"
        )
    }

    func testBodyAIPrefillsWithoutUpsert() async {
        let analyze = MockAnalyzeAPIClient()
        analyze.setBodyResult(sampleBodyAnalysis())
        let (vm, body, photo, _) = makeVMWithAnalyze(analyze: analyze)
        await vm.load()
        vm.openBodySheet()
        await vm.setBodyDraftPhoto(rawData: Self.tinyJPEG())
        XCTAssertNotNil(vm.bodyDraftPhotoData)
        await vm.runBodyAIAnalysis()

        XCTAssertEqual(analyze.bodyCallCount, 1)
        XCTAssertEqual(body.upsertCallCount, 0)
        XCTAssertEqual(photo.uploadCallCount, 0)
        XCTAssertEqual(vm.draftWeightKg, "72.5")
        XCTAssertEqual(vm.draftBodyFatPercent, "18.2")
        XCTAssertEqual(vm.draftBmi, "22.1")
        XCTAssertEqual(vm.draftMuscleKg, "50")
        XCTAssertEqual(vm.draftBoneMassKg, "2.8")
        XCTAssertEqual(vm.draftWaterPercent, "55")
        XCTAssertEqual(vm.draftBmrKcal, "1480")
        XCTAssertEqual(vm.draftVisceralFat, "7")
        XCTAssertEqual(vm.bodyAnalysisNotes, "请核对")
        // Notes must not overwrite user note field automatically.
        XCTAssertEqual(vm.draftBodyNote, "")
        XCTAssertTrue(vm.isPresentingBodySheet)
    }

    func testBodyAINullDoesNotOverwriteExistingDrafts() async {
        let seed = makeBody(dateKey: "2026-07-13", weight: 80)
        // Seed with fat/muscle-like values via a custom metric
        let existing = BodyMetric(
            id: seed.id,
            dateKey: seed.dateKey,
            measuredAt: seed.measuredAt,
            score: 0,
            weightKg: 80,
            bmi: 24,
            bodyFatPercent: 20,
            bodyAge: 0,
            bodyType: "",
            muscleKg: 48,
            skeletalMuscleKg: 0,
            boneMassKg: 3,
            waterPercent: 50,
            visceralFat: 9,
            bmrKcal: 1600,
            proteinPercent: 0,
            trunkFatPercent: 0,
            trunkMuscleKg: 0,
            leftArmFatPercent: 0,
            leftArmMuscleKg: 0,
            rightArmFatPercent: 0,
            rightArmMuscleKg: 0,
            leftLegFatPercent: 0,
            leftLegMuscleKg: 0,
            rightLegFatPercent: 0,
            rightLegMuscleKg: 0,
            note: "手填备注",
            createdAt: ""
        )
        let bodyRepo = MockBodyMetricsRepository(sessionUserId: user.id, seed: [existing])
        let analyze = MockAnalyzeAPIClient()
        // Only weight present; others null
        analyze.setBodyResult(sampleBodyAnalysis(
            weight: 81,
            fat: nil,
            bmi: nil,
            muscle: nil,
            bone: nil,
            water: nil,
            bmr: nil,
            visceral: nil,
            notes: "AI notes"
        ))
        let (vm, body, photo, _) = makeVMWithAnalyze(body: bodyRepo, analyze: analyze)
        await vm.load()
        vm.openBodySheet()
        XCTAssertEqual(vm.draftWeightKg, "80")
        XCTAssertEqual(vm.draftBodyFatPercent, "20")
        XCTAssertEqual(vm.draftBodyNote, "手填备注")
        await vm.setBodyDraftPhoto(rawData: Self.tinyJPEG())
        await vm.runBodyAIAnalysis()

        XCTAssertEqual(vm.draftWeightKg, "81")
        XCTAssertEqual(vm.draftBodyFatPercent, "20") // null did not clear
        XCTAssertEqual(vm.draftBmi, "24")
        XCTAssertEqual(vm.draftMuscleKg, "48")
        XCTAssertEqual(vm.draftBodyNote, "手填备注") // notes display-only
        XCTAssertEqual(vm.bodyAnalysisNotes, "AI notes")
        XCTAssertEqual(body.upsertCallCount, 0)
        XCTAssertEqual(photo.uploadCallCount, 0)
    }

    func testBodyAISaveUpsertsSelectedDateWithExtendedFields() async {
        let analyze = MockAnalyzeAPIClient()
        analyze.setBodyResult(sampleBodyAnalysis(date: "2026-07-01"))
        let history = "2026-07-10"
        let (vm, body, photo, _) = makeVMWithAnalyze(dateKey: history, analyze: analyze)
        await vm.load()
        vm.openBodySheet()
        await vm.setBodyDraftPhoto(rawData: Self.tinyJPEG())
        await vm.runBodyAIAnalysis()
        XCTAssertEqual(vm.selectedDateKey, history)
        XCTAssertNotNil(vm.bodyAnalysisDateHint)
        XCTAssertTrue(vm.bodyAnalysisDateHint?.contains("2026-07-01") == true)
        XCTAssertTrue(vm.bodyAnalysisDateHint?.contains(history) == true)

        await vm.saveBodyMetric()
        XCTAssertEqual(body.upsertCallCount, 1)
        XCTAssertEqual(body.lastUpsertDateKey, history)
        XCTAssertEqual(body.lastUpsertWrite?.weightKg, 72.5)
        XCTAssertEqual(body.lastUpsertWrite?.bodyFatPercent, 18.2)
        XCTAssertEqual(body.lastUpsertWrite?.bmi, 22.1)
        XCTAssertEqual(body.lastUpsertWrite?.muscleKg, 50)
        XCTAssertEqual(body.lastUpsertWrite?.boneMassKg, 2.8)
        XCTAssertEqual(body.lastUpsertWrite?.waterPercent, 55)
        XCTAssertEqual(body.lastUpsertWrite?.bmrKcal, 1480)
        XCTAssertEqual(body.lastUpsertWrite?.visceralFat, 7)
        XCTAssertEqual(photo.uploadCallCount, 0)
        XCTAssertFalse(vm.isPresentingBodySheet)
        XCTAssertNil(vm.bodyDraftPhotoData)
    }

    func testBodyAILowConfidenceStillAllowsSave() async {
        let analyze = MockAnalyzeAPIClient()
        analyze.setBodyResult(sampleBodyAnalysis(confidence: 0.3))
        let (vm, body, _, _) = makeVMWithAnalyze(analyze: analyze)
        vm.openBodySheet()
        await vm.setBodyDraftPhoto(rawData: Self.tinyJPEG())
        await vm.runBodyAIAnalysis()
        XCTAssertTrue(vm.showBodyLowConfidenceWarning)
        await vm.saveBodyMetric()
        XCTAssertEqual(body.upsertCallCount, 1)
    }

    func testBodyAIErrorKeepsDraftAndNoUpsert() async {
        let analyze = MockAnalyzeAPIClient()
        analyze.setBodyError(AppError.unauthorized)
        let (vm, body, photo, _) = makeVMWithAnalyze(analyze: analyze)
        vm.openBodySheet()
        vm.draftWeightKg = "70"
        vm.draftBodyNote = "保留"
        await vm.setBodyDraftPhoto(rawData: Self.tinyJPEG())
        await vm.runBodyAIAnalysis()
        XCTAssertEqual(body.upsertCallCount, 0)
        XCTAssertEqual(photo.uploadCallCount, 0)
        XCTAssertEqual(vm.draftWeightKg, "70")
        XCTAssertEqual(vm.draftBodyNote, "保留")
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertFalse((vm.errorMessage ?? "").contains("eyJ"))
        XCTAssertTrue(vm.isPresentingBodySheet)
    }

    func testBodyAINetworkErrorMessageSafe() async {
        let analyze = MockAnalyzeAPIClient()
        analyze.setBodyError(AppError.network(message: "network down"))
        let (vm, body, _, _) = makeVMWithAnalyze(analyze: analyze)
        vm.openBodySheet()
        await vm.setBodyDraftPhoto(rawData: Self.tinyJPEG())
        await vm.runBodyAIAnalysis()
        XCTAssertEqual(body.upsertCallCount, 0)
        XCTAssertEqual(vm.errorMessage, AppError.network(message: "network down").userMessage)
    }

    func testBodySheetDismissClearsScreenshot() async {
        let analyze = MockAnalyzeAPIClient()
        let (vm, _, photo, _) = makeVMWithAnalyze(analyze: analyze)
        vm.openBodySheet()
        await vm.setBodyDraftPhoto(rawData: Self.tinyJPEG())
        XCTAssertNotNil(vm.bodyDraftPhotoData)
        vm.clearBodySessionAfterDismiss()
        XCTAssertNil(vm.bodyDraftPhotoData)
        XCTAssertNil(vm.bodyDraftPhotoPreview)
        XCTAssertNil(vm.lastBodyAnalysis)
        XCTAssertEqual(photo.uploadCallCount, 0)
    }

    func testBodyCancelClearsScreenshot() async {
        let (vm, _, photo, _) = makeVMWithAnalyze(analyze: MockAnalyzeAPIClient())
        vm.openBodySheet()
        await vm.setBodyDraftPhoto(rawData: Self.tinyJPEG())
        vm.cancelBodySheet()
        XCTAssertNil(vm.bodyDraftPhotoData)
        XCTAssertFalse(vm.isPresentingBodySheet)
        XCTAssertEqual(photo.uploadCallCount, 0)
    }

    func testBodyNegativeMetricDoesNotUpsert() async {
        let (vm, body, _, _) = makeVMWithAnalyze(analyze: MockAnalyzeAPIClient())
        vm.openBodySheet()
        vm.draftWeightKg = "70"
        vm.draftMuscleKg = "-1"
        await vm.saveBodyMetric()
        XCTAssertEqual(body.upsertCallCount, 0)
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertTrue(vm.isPresentingBodySheet)
    }

    func testBodyWaterOutOfRangeDoesNotUpsert() async {
        let (vm, body, _, _) = makeVMWithAnalyze(analyze: MockAnalyzeAPIClient())
        vm.openBodySheet()
        vm.draftWeightKg = "70"
        vm.draftWaterPercent = "101"
        await vm.saveBodyMetric()
        XCTAssertEqual(body.upsertCallCount, 0)
        XCTAssertTrue((vm.errorMessage ?? "").contains("水分") || (vm.errorMessage ?? "").contains("0–100"))
    }

    func testBodyAIDoesNotCallPhotoUpload() async {
        let analyze = MockAnalyzeAPIClient()
        analyze.setBodyResult(sampleBodyAnalysis())
        let (vm, body, photo, _) = makeVMWithAnalyze(analyze: analyze)
        vm.openBodySheet()
        await vm.setBodyDraftPhoto(rawData: Self.tinyJPEG())
        await vm.runBodyAIAnalysis()
        await vm.saveBodyMetric()
        XCTAssertEqual(photo.uploadCallCount, 0)
        XCTAssertTrue(photo.deletedPaths.isEmpty)
        XCTAssertEqual(body.upsertCallCount, 1)
        XCTAssertNotNil(analyze.lastBodyRequest)
        XCTAssertTrue(analyze.lastBodyRequest?.isLocalDataURL == true)
        XCTAssertFalse(analyze.lastBodyRequest?.containsRemotePhotoURL == true)
    }

    // MARK: - Fixtures

    private func makeBody(dateKey: String, weight: Double) -> BodyMetric {
        BodyMetric(
            id: UUID().uuidString,
            dateKey: dateKey,
            measuredAt: "\(dateKey)T12:00:00",
            score: 0,
            weightKg: weight,
            bmi: 0,
            bodyFatPercent: 0,
            bodyAge: 0,
            bodyType: "",
            muscleKg: 0,
            skeletalMuscleKg: 0,
            boneMassKg: 0,
            waterPercent: 0,
            visceralFat: 0,
            bmrKcal: 0,
            proteinPercent: 0,
            trunkFatPercent: 0,
            trunkMuscleKg: 0,
            leftArmFatPercent: 0,
            leftArmMuscleKg: 0,
            rightArmFatPercent: 0,
            rightArmMuscleKg: 0,
            leftLegFatPercent: 0,
            leftLegMuscleKg: 0,
            rightLegFatPercent: 0,
            rightLegMuscleKg: 0,
            note: "",
            createdAt: ""
        )
    }

    /// Valid tiny JPEG so ImageCompressor accepts the bytes.
    private static func tinyJPEG(width: Int = 16, height: Int = 16) -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            fatalError("CGContext unavailable")
        }
        ctx.setFillColor(red: 0.3, green: 0.5, blue: 0.7, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let cgImage = ctx.makeImage() else {
            fatalError("CGImage unavailable")
        }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            fatalError("JPEG destination unavailable")
        }
        CGImageDestinationAddImage(dest, cgImage, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            fatalError("JPEG finalize failed")
        }
        return data as Data
    }

    private func makeDaily(dateKey: String, steps: Double, active: Double = 0) -> DailyActivity {
        DailyActivity(
            id: UUID().uuidString,
            dateKey: dateKey,
            source: "manual",
            steps: steps,
            activeCalories: active,
            totalCalories: active,
            exerciseMinutes: 0,
            standHours: 0,
            distanceKm: 0,
            floors: 0,
            restingHeartRate: 0,
            hrvMs: 0,
            sleepMinutes: 0,
            rawMetrics: [:],
            note: "",
            createdAt: ""
        )
    }

    private func makeExercise(dateKey: String, title: String, cal: Double) -> ExerciseActivity {
        ExerciseActivity(
            id: UUID().uuidString,
            dateKey: dateKey,
            startedAt: "\(dateKey)T12:00:00",
            source: "manual",
            externalId: "",
            type: title,
            title: title,
            durationMinutes: 30,
            distanceKm: 0,
            activeCalories: cal,
            avgHeartRate: 0,
            maxHeartRate: 0,
            elevationGainM: 0,
            note: "",
            createdAt: ""
        )
    }
}
