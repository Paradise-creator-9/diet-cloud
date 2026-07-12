import XCTest
@testable import DietCloud

@MainActor
final class HealthKitImportTests: XCTestCase {
    private let user = AuthUser(id: "11111111-1111-1111-1111-111111111111", email: "a@example.com")

    private func makeVM(
        dateKey: String = "2026-07-13",
        health: MockHealthKitClient,
        body: MockBodyMetricsRepository? = nil,
        daily: MockDailyActivityRepository? = nil,
        exercise: MockExerciseActivityRepository? = nil
    ) -> (
        TodayMealsViewModel,
        MockBodyMetricsRepository,
        MockDailyActivityRepository,
        MockExerciseActivityRepository
    ) {
        let photo = MockMealPhotoRepository(sessionUserId: user.id)
        let bodyRepo = body ?? MockBodyMetricsRepository(sessionUserId: user.id)
        let dailyRepo = daily ?? MockDailyActivityRepository(sessionUserId: user.id)
        let exerciseRepo = exercise ?? MockExerciseActivityRepository(sessionUserId: user.id)
        let importer = HealthKitImportService(
            bodyRepository: bodyRepo,
            dailyRepository: dailyRepo,
            exerciseRepository: exerciseRepo
        )
        let vm = TodayMealsViewModel(
            user: user,
            foodRepository: MockFoodItemRepository(sessionUserId: user.id, photoRepository: photo),
            photoRepository: photo,
            analyzeAPI: MockAnalyzeAPIClient(),
            bodyRepository: bodyRepo,
            dailyActivityRepository: dailyRepo,
            exerciseRepository: exerciseRepo,
            healthKitClient: health,
            healthKitImporter: importer,
            dateKey: dateKey
        )
        return (vm, bodyRepo, dailyRepo, exerciseRepo)
    }

    func testUnavailableShowsSafeError() async {
        let health = MockHealthKitClient()
        health.isAvailable = false
        let (vm, _, _, _) = makeVM(health: health)
        await vm.importFromHealthKit()
        XCTAssertEqual(vm.healthKitStatusMessage, HealthKitError.unavailable.userMessage)
        XCTAssertFalse((vm.healthKitStatusMessage ?? "").contains("eyJ"))
    }

    func testAuthorizationDeniedDoesNotImport() async {
        let health = MockHealthKitClient()
        health.status = .denied
        health.snapshot = HealthKitDaySnapshot(
            dateKey: "2026-07-13",
            steps: 1000,
            activeCalories: 200,
            distanceKm: 1,
            weightKg: nil,
            bodyFatPercent: nil,
            workouts: []
        )
        let (vm, _, daily, _) = makeVM(health: health)
        await vm.importFromHealthKit()
        XCTAssertEqual(vm.healthKitStatusMessage, HealthKitError.authorizationDenied.userMessage)
        XCTAssertNil(daily.lastUpsertDateKey)
    }

    func testImportTodayWritesTodayDateKey() async {
        let health = MockHealthKitClient()
        health.snapshot = HealthKitDaySnapshot(
            dateKey: "2026-07-13",
            steps: 8000,
            activeCalories: 400,
            distanceKm: 5,
            weightKg: 76,
            bodyFatPercent: 18,
            workouts: [
                HealthKitWorkoutSample(
                    externalId: "wk-1",
                    type: "骑行",
                    title: "骑行",
                    startedAt: "2026-07-13T08:00:00Z",
                    durationMinutes: 30,
                    activeCalories: 250,
                    distanceKm: 10
                ),
            ]
        )
        let (vm, body, daily, exercise) = makeVM(dateKey: "2026-07-13", health: health)
        await vm.importFromHealthKit()
        XCTAssertEqual(health.lastFetchDateKey, "2026-07-13")
        XCTAssertEqual(daily.lastUpsertDateKey, "2026-07-13")
        XCTAssertEqual(body.lastUpsertDateKey, "2026-07-13")
        XCTAssertEqual(exercise.lastCreateDateKey, "2026-07-13")
        XCTAssertEqual(vm.dailyActivity?.source, "healthkit")
        XCTAssertEqual(vm.dailyActivity?.steps, 8000)
        XCTAssertEqual(vm.bodyMetric?.weightKg, 76)
        XCTAssertEqual(vm.exercises.count, 1)
        XCTAssertEqual(vm.exercises.first?.source, "healthkit")
        XCTAssertEqual(vm.exercises.first?.externalId, "wk-1")
    }

    func testImportYesterdayWritesYesterdayDateKey() async {
        let health = MockHealthKitClient()
        health.snapshot = HealthKitDaySnapshot(
            dateKey: "ignored",
            steps: 100,
            activeCalories: 50,
            distanceKm: nil,
            weightKg: nil,
            bodyFatPercent: nil,
            workouts: []
        )
        let (vm, _, daily, _) = makeVM(dateKey: "2026-07-10", health: health)
        await vm.importFromHealthKit()
        XCTAssertEqual(health.lastFetchDateKey, "2026-07-10")
        XCTAssertEqual(daily.lastUpsertDateKey, "2026-07-10")
        XCTAssertEqual(vm.selectedDateKey, "2026-07-10")
    }

    func testManualDailyNotSilentlyOverwritten() async {
        let existing = DailyActivity(
            id: "manual-1",
            dateKey: "2026-07-13",
            source: "manual",
            steps: 111,
            activeCalories: 22,
            totalCalories: 22,
            exerciseMinutes: 0,
            standHours: 0,
            distanceKm: 0,
            floors: 0,
            restingHeartRate: 0,
            hrvMs: 0,
            sleepMinutes: 0,
            rawMetrics: [:],
            note: "手动",
            createdAt: ""
        )
        let dailyRepo = MockDailyActivityRepository(sessionUserId: user.id, seed: [existing])
        let health = MockHealthKitClient()
        health.snapshot = HealthKitDaySnapshot(
            dateKey: "2026-07-13",
            steps: 9999,
            activeCalories: 500,
            distanceKm: 3,
            weightKg: nil,
            bodyFatPercent: nil,
            workouts: []
        )
        let (vm, _, daily, _) = makeVM(health: health, daily: dailyRepo)
        await vm.load()
        await vm.importFromHealthKit(overwriteManual: false)
        XCTAssertTrue(vm.isPresentingHealthKitOverwriteConfirm)
        // Manual data still preferred until confirm
        XCTAssertEqual(vm.dailyActivity?.steps, 111)
        XCTAssertNil(daily.lastUpsertDateKey)
    }

    func testConfirmOverwriteUpdatesManualDaily() async {
        let existing = DailyActivity(
            id: "manual-1",
            dateKey: "2026-07-13",
            source: "manual",
            steps: 111,
            activeCalories: 22,
            totalCalories: 22,
            exerciseMinutes: 0,
            standHours: 0,
            distanceKm: 0,
            floors: 0,
            restingHeartRate: 0,
            hrvMs: 0,
            sleepMinutes: 0,
            rawMetrics: [:],
            note: "手动",
            createdAt: ""
        )
        let dailyRepo = MockDailyActivityRepository(sessionUserId: user.id, seed: [existing])
        let health = MockHealthKitClient()
        health.snapshot = HealthKitDaySnapshot(
            dateKey: "2026-07-13",
            steps: 8000,
            activeCalories: 400,
            distanceKm: 5,
            weightKg: nil,
            bodyFatPercent: nil,
            workouts: []
        )
        let (vm, _, _, _) = makeVM(health: health, daily: dailyRepo)
        await vm.load()
        await vm.importFromHealthKit(overwriteManual: false)
        XCTAssertTrue(vm.isPresentingHealthKitOverwriteConfirm)
        await vm.confirmHealthKitOverwriteImport()
        XCTAssertFalse(vm.isPresentingHealthKitOverwriteConfirm)
        XCTAssertEqual(vm.dailyActivity?.source, "healthkit")
        XCTAssertEqual(vm.dailyActivity?.steps, 8000)
    }

    func testManualBodyNotSilentlyOverwritten() async {
        let bodyRepo = MockBodyMetricsRepository(
            sessionUserId: user.id,
            seed: [
                BodyMetric(
                    id: "b1",
                    dateKey: "2026-07-13",
                    measuredAt: "",
                    score: 0,
                    weightKg: 70,
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
                    note: "手动",
                    createdAt: ""
                ),
            ]
        )
        let health = MockHealthKitClient()
        health.snapshot = HealthKitDaySnapshot(
            dateKey: "2026-07-13",
            steps: nil,
            activeCalories: nil,
            distanceKm: nil,
            weightKg: 80,
            bodyFatPercent: 20,
            workouts: []
        )
        let (vm, body, _, _) = makeVM(health: health, body: bodyRepo)
        await vm.load()
        await vm.importFromHealthKit(overwriteManual: false)
        XCTAssertTrue(vm.isPresentingHealthKitOverwriteConfirm)
        XCTAssertEqual(vm.bodyMetric?.weightKg, 70)
        XCTAssertNil(body.lastUpsertDateKey)
    }

    func testWorkoutDedupByExternalId() async {
        let existing = ExerciseActivity(
            id: "e1",
            dateKey: "2026-07-13",
            startedAt: "2026-07-13T08:00:00Z",
            source: "healthkit",
            externalId: "wk-dup",
            type: "骑行",
            title: "骑行",
            durationMinutes: 30,
            distanceKm: 10,
            activeCalories: 250,
            avgHeartRate: 0,
            maxHeartRate: 0,
            elevationGainM: 0,
            note: "",
            createdAt: ""
        )
        let exerciseRepo = MockExerciseActivityRepository(sessionUserId: user.id, seed: [existing])
        let health = MockHealthKitClient()
        health.snapshot = HealthKitDaySnapshot(
            dateKey: "2026-07-13",
            steps: 100,
            activeCalories: 50,
            distanceKm: nil,
            weightKg: nil,
            bodyFatPercent: nil,
            workouts: [
                HealthKitWorkoutSample(
                    externalId: "wk-dup",
                    type: "骑行",
                    title: "骑行",
                    startedAt: "2026-07-13T08:00:00Z",
                    durationMinutes: 30,
                    activeCalories: 250,
                    distanceKm: 10
                ),
                HealthKitWorkoutSample(
                    externalId: "wk-new",
                    type: "步行",
                    title: "步行",
                    startedAt: "2026-07-13T18:00:00Z",
                    durationMinutes: 20,
                    activeCalories: 80,
                    distanceKm: 2
                ),
            ]
        )
        let (vm, _, _, _) = makeVM(health: health, exercise: exerciseRepo)
        await vm.load()
        await vm.importFromHealthKit()
        XCTAssertEqual(vm.exercises.count, 2)
        XCTAssertEqual(Set(vm.exercises.map(\.externalId)), Set(["wk-dup", "wk-new"]))
    }

    func testDayEnergyDoesNotDoubleCountHealthKitActiveAndWorkouts() async {
        let daily = DailyActivity(
            id: "d1",
            dateKey: "2026-07-13",
            source: "healthkit",
            steps: 8000,
            activeCalories: 600, // includes workouts
            totalCalories: 600,
            exerciseMinutes: 0,
            standHours: 0,
            distanceKm: 5,
            floors: 0,
            restingHeartRate: 0,
            hrvMs: 0,
            sleepMinutes: 0,
            rawMetrics: [:],
            note: "",
            createdAt: ""
        )
        let exercise = ExerciseActivity(
            id: "e1",
            dateKey: "2026-07-13",
            startedAt: "",
            source: "healthkit",
            externalId: "wk-1",
            type: "骑行",
            title: "骑行",
            durationMinutes: 30,
            distanceKm: 10,
            activeCalories: 250,
            avgHeartRate: 0,
            maxHeartRate: 0,
            elevationGainM: 0,
            note: "",
            createdAt: ""
        )
        let food = FoodItem(
            id: "f1",
            dateKey: "2026-07-13",
            meal: .lunch,
            name: "饭",
            grams: 0,
            calories: 1000,
            protein: 0,
            carbs: 0,
            fat: 0,
            fiber: 0,
            note: "",
            photoPaths: [],
            photoURLs: [],
            createdAt: "",
            sourceId: nil
        )
        let photo = MockMealPhotoRepository(sessionUserId: user.id)
        let vm = TodayMealsViewModel(
            user: user,
            foodRepository: MockFoodItemRepository(sessionUserId: user.id, seed: [food], photoRepository: photo),
            photoRepository: photo,
            analyzeAPI: MockAnalyzeAPIClient(),
            bodyRepository: MockBodyMetricsRepository(sessionUserId: user.id),
            dailyActivityRepository: MockDailyActivityRepository(sessionUserId: user.id, seed: [daily]),
            exerciseRepository: MockExerciseActivityRepository(sessionUserId: user.id, seed: [exercise]),
            healthKitClient: MockHealthKitClient(),
            dateKey: "2026-07-13"
        )
        await vm.load()
        // 方案 B: net = intake - healthkit daily only = 1000 - 600 = 400 (not 1000-600-250)
        XCTAssertEqual(vm.dayEnergySummary.activityBurnKcal, 600)
        XCTAssertEqual(vm.dayEnergySummary.exerciseBurnKcal, 250)
        XCTAssertEqual(vm.dayEnergySummary.dailyActivitySource, "healthkit")
        XCTAssertEqual(vm.dayEnergySummary.netKcal, 400)
    }

    func testManualDailyStillSubtractsExerciseFromNet() async {
        let daily = DailyActivity(
            id: "d1",
            dateKey: "2026-07-13",
            source: "manual",
            steps: 1000,
            activeCalories: 100,
            totalCalories: 100,
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
        let exercise = ExerciseActivity(
            id: "e1",
            dateKey: "2026-07-13",
            startedAt: "",
            source: "manual",
            externalId: "",
            type: "骑行",
            title: "骑行",
            durationMinutes: 30,
            distanceKm: 0,
            activeCalories: 200,
            avgHeartRate: 0,
            maxHeartRate: 0,
            elevationGainM: 0,
            note: "",
            createdAt: ""
        )
        let food = FoodItem(
            id: "f1",
            dateKey: "2026-07-13",
            meal: .lunch,
            name: "饭",
            grams: 0,
            calories: 800,
            protein: 0,
            carbs: 0,
            fat: 0,
            fiber: 0,
            note: "",
            photoPaths: [],
            photoURLs: [],
            createdAt: "",
            sourceId: nil
        )
        let photo = MockMealPhotoRepository(sessionUserId: user.id)
        let vm = TodayMealsViewModel(
            user: user,
            foodRepository: MockFoodItemRepository(sessionUserId: user.id, seed: [food], photoRepository: photo),
            photoRepository: photo,
            analyzeAPI: MockAnalyzeAPIClient(),
            bodyRepository: MockBodyMetricsRepository(sessionUserId: user.id),
            dailyActivityRepository: MockDailyActivityRepository(sessionUserId: user.id, seed: [daily]),
            exerciseRepository: MockExerciseActivityRepository(sessionUserId: user.id, seed: [exercise]),
            dateKey: "2026-07-13"
        )
        await vm.load()
        XCTAssertEqual(vm.dayEnergySummary.netKcal, 500) // 800 - 100 - 200
    }

    func testNoDataMessageSafe() async {
        let health = MockHealthKitClient()
        health.error = HealthKitError.noData
        let (vm, _, _, _) = makeVM(health: health)
        await vm.importFromHealthKit()
        XCTAssertEqual(vm.healthKitStatusMessage, HealthKitError.noData.userMessage)
        XCTAssertFalse((vm.healthKitStatusMessage ?? "").contains(user.id))
    }

    func testImportServiceMapping() async throws {
        let body = MockBodyMetricsRepository(sessionUserId: user.id)
        let daily = MockDailyActivityRepository(sessionUserId: user.id)
        let exercise = MockExerciseActivityRepository(sessionUserId: user.id)
        let service = HealthKitImportService(
            bodyRepository: body,
            dailyRepository: daily,
            exerciseRepository: exercise
        )
        let snap = HealthKitDaySnapshot(
            dateKey: "2026-07-13",
            steps: 1234,
            activeCalories: 321,
            distanceKm: 2.5,
            weightKg: 75.5,
            bodyFatPercent: 19,
            workouts: [
                HealthKitWorkoutSample(
                    externalId: "uuid-1",
                    type: "跑步",
                    title: "跑步",
                    startedAt: "2026-07-13T07:00:00Z",
                    durationMinutes: 40,
                    activeCalories: 400,
                    distanceKm: 6
                ),
            ]
        )
        let result = try await service.importDay(
            dateKey: "2026-07-13",
            snapshot: snap,
            existingBody: nil,
            existingDaily: nil,
            existingExercises: [],
            overwriteManual: false
        )
        XCTAssertTrue(result.importedDaily)
        XCTAssertTrue(result.importedBody)
        XCTAssertEqual(result.importedWorkouts, 1)
        XCTAssertEqual(daily.lastUpsertDateKey, "2026-07-13")
        XCTAssertEqual(body.lastUpsertDateKey, "2026-07-13")
        XCTAssertEqual(exercise.lastCreateDateKey, "2026-07-13")
    }
}
