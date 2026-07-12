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
        XCTAssertEqual(vm.dayEnergySummary.netKcal, 50)
        XCTAssertEqual(vm.dayEnergySummary.weightKg, 76)
        XCTAssertEqual(vm.dayEnergySummary.steps, 8000)
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
