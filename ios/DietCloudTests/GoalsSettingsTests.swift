import XCTest
@testable import DietCloud

final class UserGoalsValidationTests: XCTestCase {
    func testValidGoalsSave() {
        let (goals, error) = UserGoalsValidation.validate(
            caloriesText: "2000",
            weightText: "70",
            proteinText: "120",
            carbsText: "200",
            fiberText: "25"
        )
        XCTAssertNil(error)
        XCTAssertEqual(goals?.dailyCaloriesKcal, 2000)
        XCTAssertEqual(goals?.targetWeightKg, 70)
        XCTAssertEqual(goals?.proteinGrams, 120)
        XCTAssertEqual(goals?.carbsGrams, 200)
        XCTAssertEqual(goals?.fiberGrams, 25)
        XCTAssertNil(goals?.fatGrams)
    }

    func testEmptyFieldsClearGoals() {
        let (goals, error) = UserGoalsValidation.validate(
            caloriesText: "",
            weightText: "",
            proteinText: "",
            carbsText: "",
            fiberText: ""
        )
        XCTAssertNil(error)
        XCTAssertEqual(goals, .empty)
        XCTAssertFalse(goals?.hasAnyGoal == true && goals == nil)
        XCTAssertEqual(goals?.hasAnyGoal, false)
    }

    func testCaloriesMustBePositive() {
        let (g1, zeroMsg) = UserGoalsValidation.validate(
            caloriesText: "0",
            weightText: "",
            proteinText: "",
            carbsText: "",
            fiberText: ""
        )
        XCTAssertNil(g1)
        XCTAssertTrue((zeroMsg ?? "").contains("热量") || (zeroMsg ?? "").contains("大于"))

        let (g2, negMsg) = UserGoalsValidation.validate(
            caloriesText: "-100",
            weightText: "",
            proteinText: "",
            carbsText: "",
            fiberText: ""
        )
        XCTAssertNil(g2)
        XCTAssertNotNil(negMsg)
    }

    func testWeightMustBePositive() {
        let (goals, message) = UserGoalsValidation.validate(
            caloriesText: "",
            weightText: "0",
            proteinText: "",
            carbsText: "",
            fiberText: ""
        )
        XCTAssertNil(goals)
        XCTAssertTrue((message ?? "").contains("体重") || (message ?? "").contains("大于"))
    }

    func testMacrosCannotBeNegative() {
        let (goals, message) = UserGoalsValidation.validate(
            caloriesText: "",
            weightText: "",
            proteinText: "-1",
            carbsText: "",
            fiberText: ""
        )
        XCTAssertNil(goals)
        XCTAssertTrue((message ?? "").contains("蛋白质") || (message ?? "").contains("负"))
    }

    func testFiberCannotBeNegative() {
        let (goals, message) = UserGoalsValidation.validate(
            caloriesText: "",
            weightText: "",
            proteinText: "",
            carbsText: "",
            fiberText: "-2"
        )
        XCTAssertNil(goals)
        XCTAssertTrue((message ?? "").contains("纤维") || (message ?? "").contains("负"))
    }
}

final class GoalsStoreTests: XCTestCase {
    func testInMemorySaveAndLoad() {
        let store = InMemoryGoalsStore()
        let goals = UserGoals(
            dailyCaloriesKcal: 1800,
            targetWeightKg: 68,
            proteinGrams: 100,
            carbsGrams: nil,
            fiberGrams: 25,
            fatGrams: nil
        )
        store.save(goals)
        XCTAssertEqual(store.goals.dailyCaloriesKcal, 1800)
        XCTAssertEqual(store.goals.targetWeightKg, 68)
        XCTAssertNil(store.goals.carbsGrams)
        XCTAssertEqual(store.goals.fiberGrams, 25)
    }

    func testUserDefaultsRoundTripIncludingFiber() {
        let suite = "dietcloud.tests.goals.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = UserDefaultsGoalsStore(defaults: defaults)
        store.save(
            UserGoals(
                dailyCaloriesKcal: 2100,
                targetWeightKg: 72.5,
                proteinGrams: 110,
                carbsGrams: 220,
                fiberGrams: 30,
                fatGrams: nil
            )
        )
        let reloaded = UserDefaultsGoalsStore(defaults: defaults)
        XCTAssertEqual(reloaded.goals.dailyCaloriesKcal, 2100)
        XCTAssertEqual(reloaded.goals.targetWeightKg, 72.5)
        XCTAssertEqual(reloaded.goals.proteinGrams, 110)
        XCTAssertEqual(reloaded.goals.fiberGrams, 30)
    }

    /// Stage 10: old installs wrote `fatGrams` only (no `fiberGrams`).
    func testLegacyUserDefaultsJSONWithFatGramsStillDecodes() throws {
        // Exact shape produced by pre-fiber UserGoals Codable.
        let legacyJSON = """
        {
          "dailyCaloriesKcal": 2000,
          "targetWeightKg": 70,
          "proteinGrams": 120,
          "carbsGrams": 200,
          "fatGrams": 60
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(UserGoals.self, from: legacyJSON)
        XCTAssertEqual(decoded.dailyCaloriesKcal, 2000)
        XCTAssertEqual(decoded.targetWeightKg, 70)
        XCTAssertEqual(decoded.proteinGrams, 120)
        XCTAssertEqual(decoded.carbsGrams, 200)
        XCTAssertEqual(decoded.fatGrams, 60)
        // Missing fiber key → nil, NOT copied from fat.
        XCTAssertNil(decoded.fiberGrams)
        XCTAssertNotEqual(decoded.fiberGrams, decoded.fatGrams)

        let suite = "dietcloud.tests.goals.legacy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(legacyJSON, forKey: UserDefaultsGoalsStore.storageKey)

        let store = UserDefaultsGoalsStore(defaults: defaults)
        XCTAssertEqual(store.goals.fatGrams, 60)
        XCTAssertNil(store.goals.fiberGrams)
        XCTAssertEqual(store.goals.dailyCaloriesKcal, 2000)
        XCTAssertTrue(store.goals.hasAnyGoal)
        XCTAssertTrue(store.goals.hasHomeNutrientGoal) // protein/carbs present
    }

    @MainActor
    func testLegacyFatIsNotMigratedToFiberOnDecodeOrSettingsSave() {
        let suite = "dietcloud.tests.goals.nomigrate.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let legacyJSON = """
        {"dailyCaloriesKcal":1800,"proteinGrams":90,"fatGrams":55}
        """.data(using: .utf8)!
        defaults.set(legacyJSON, forKey: UserDefaultsGoalsStore.storageKey)

        let store = UserDefaultsGoalsStore(defaults: defaults)
        XCTAssertEqual(store.goals.fatGrams, 55)
        XCTAssertNil(store.goals.fiberGrams)

        // Settings save updates fiber without copying fat into fiber.
        let user = AuthUser(id: "11111111-1111-1111-1111-111111111111", email: "a@b.com")
        let vm = SettingsViewModel(
            user: user,
            goalsStore: store,
            notificationScheduler: MockNotificationScheduler(status: .authorized),
            onSignOut: {}
        )
        vm.draftCalories = "1800"
        vm.draftProtein = "90"
        vm.draftFiber = "25"
        XCTAssertTrue(vm.saveGoals())
        XCTAssertEqual(store.goals.fiberGrams, 25)
        XCTAssertEqual(store.goals.fatGrams, 55, "legacy fat must be preserved, not cleared or remapped")
        XCTAssertNotEqual(store.goals.fiberGrams, store.goals.fatGrams)
    }

    func testMissingFiberKeyUsesNilNotSyntheticDefault() throws {
        let json = #"{"dailyCaloriesKcal":2000}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(UserGoals.self, from: json)
        XCTAssertNil(decoded.fiberGrams)
        XCTAssertNil(decoded.fatGrams)
        XCTAssertEqual(decoded.dailyCaloriesKcal, 2000)
    }
}

@MainActor
final class SettingsViewModelTests: XCTestCase {
    private let user = AuthUser(id: "11111111-1111-1111-1111-111111111111", email: "user@example.com")

    func testSaveGoalsPersistsAndRejectsInvalid() {
        let store = InMemoryGoalsStore()
        var signedOut = false
        let vm = SettingsViewModel(
            user: user,
            goalsStore: store,
            notificationScheduler: MockNotificationScheduler(status: .authorized),
            onSignOut: { signedOut = true }
        )
        vm.draftCalories = "2000"
        vm.draftWeight = "70"
        vm.draftProtein = "100"
        vm.draftCarbs = "200"
        vm.draftFiber = "25"
        XCTAssertTrue(vm.saveGoals())
        XCTAssertEqual(store.goals.dailyCaloriesKcal, 2000)
        XCTAssertEqual(store.goals.fiberGrams, 25)
        XCTAssertNil(vm.errorMessage)
        XCTAssertNotNil(vm.statusMessage)

        vm.draftCalories = "0"
        XCTAssertFalse(vm.saveGoals())
        XCTAssertNotNil(vm.errorMessage)
        // Previous valid goals remain until successful save of invalid is rejected
        XCTAssertEqual(store.goals.dailyCaloriesKcal, 2000)
        _ = signedOut
    }

    func testSignOutRequiresConfirmThenCallsHandler() {
        let store = InMemoryGoalsStore()
        var signedOut = false
        let vm = SettingsViewModel(
            user: user,
            goalsStore: store,
            notificationScheduler: MockNotificationScheduler(status: .authorized),
            onSignOut: { signedOut = true }
        )
        XCTAssertFalse(vm.isPresentingSignOutConfirm)
        vm.requestSignOut()
        XCTAssertTrue(vm.isPresentingSignOutConfirm)
        XCTAssertFalse(signedOut)
        vm.cancelSignOut()
        XCTAssertFalse(vm.isPresentingSignOutConfirm)
        XCTAssertFalse(signedOut)
        vm.requestSignOut()
        vm.confirmSignOut()
        XCTAssertTrue(signedOut)
        XCTAssertFalse(vm.isPresentingSignOutConfirm)
    }

    func testRedactedEmailDoesNotExposeFullLocalPart() {
        XCTAssertEqual(user.redactedEmail, "u***@example.com")
        XCTAssertFalse(user.redactedEmail.contains("user@"))
    }
}

@MainActor
final class GoalsOverviewTests: XCTestCase {
    private let user = AuthUser(id: "11111111-1111-1111-1111-111111111111", email: "a@example.com")

    func testGoalsProgressLinesWithAndWithoutGoals() {
        let withGoals = GoalsProgress(
            intakeKcal: 500,
            netKcal: 300,
            proteinG: 40,
            carbsG: 50,
            fiberG: 10,
            goals: UserGoals(
                dailyCaloriesKcal: 2000,
                targetWeightKg: 70,
                proteinGrams: 120,
                carbsGrams: 200,
                fiberGrams: 25,
                fatGrams: nil
            )
        )
        XCTAssertEqual(withGoals.intakeLine, "500 / 2000 kcal")
        XCTAssertEqual(withGoals.netLine, "300 / 2000 kcal")
        XCTAssertEqual(withGoals.proteinLine, "40 / 120 g")
        XCTAssertEqual(withGoals.carbsLine, "50 / 200 g")
        XCTAssertEqual(withGoals.fiberLine, "10 / 25 g")
        XCTAssertEqual(withGoals.intakeProgress, 0.25, accuracy: 0.0001)
        XCTAssertEqual(withGoals.netProgress, 0.15, accuracy: 0.0001)
        XCTAssertEqual(withGoals.proteinProgress, 40.0 / 120.0, accuracy: 0.0001)
        XCTAssertEqual(withGoals.fiberProgress, 10.0 / 25.0, accuracy: 0.0001)

        let without = GoalsProgress(
            intakeKcal: 500,
            netKcal: 300,
            proteinG: 40,
            carbsG: 50,
            fiberG: 10,
            goals: .empty
        )
        XCTAssertEqual(without.intakeLine, "500 kcal")
        XCTAssertEqual(without.netLine, "300 kcal")
        XCTAssertEqual(without.proteinLine, "40 g")
        XCTAssertEqual(without.fiberLine, "10 g")
        XCTAssertFalse(without.goals.hasAnyGoal)
        XCTAssertEqual(without.intakeProgress, 0)
        XCTAssertEqual(without.netProgress, 0)
        XCTAssertEqual(without.fiberProgress, 0)
    }

    func testProgressClampedToUnitInterval() {
        XCTAssertEqual(GoalsProgress.clampedRatio(current: -10, goal: 100), 0)
        XCTAssertEqual(GoalsProgress.clampedRatio(current: 0, goal: 100), 0)
        XCTAssertEqual(GoalsProgress.clampedRatio(current: 50, goal: 100), 0.5, accuracy: 0.0001)
        XCTAssertEqual(GoalsProgress.clampedRatio(current: 100, goal: 100), 1)
        XCTAssertEqual(GoalsProgress.clampedRatio(current: 250, goal: 100), 1) // over goal
        XCTAssertEqual(GoalsProgress.clampedRatio(current: 50, goal: nil), 0)
        XCTAssertEqual(GoalsProgress.clampedRatio(current: 50, goal: 0), 0)
        XCTAssertEqual(GoalsProgress.clampedRatio(current: .nan, goal: 100), 0)
        XCTAssertEqual(GoalsProgress.clampedRatio(current: .infinity, goal: 100), 0)

        let over = GoalsProgress(
            intakeKcal: 2500,
            netKcal: -100,
            proteinG: 200,
            carbsG: 10,
            fiberG: 40,
            goals: UserGoals(
                dailyCaloriesKcal: 2000,
                targetWeightKg: nil,
                proteinGrams: 100,
                carbsGrams: nil,
                fiberGrams: 25,
                fatGrams: nil
            )
        )
        XCTAssertEqual(over.intakeProgress, 1)
        XCTAssertEqual(over.netProgress, 0) // negative net → 0
        XCTAssertEqual(over.proteinProgress, 1)
        XCTAssertEqual(over.fiberProgress, 1) // 40/25 clamped
        XCTAssertTrue(over.isOverGoal(current: 2500, goal: 2000))
        XCTAssertFalse(over.isOverGoal(current: 100, goal: 2000))
        XCTAssertTrue(over.isOverGoal(current: 40, goal: 25))
    }

    func testEmptyGoalsProgressDoesNotCrash() {
        let empty = GoalsProgress(
            intakeKcal: 0,
            netKcal: 0,
            proteinG: 0,
            carbsG: 0,
            fiberG: 0,
            goals: .empty
        )
        XCTAssertEqual(empty.intakeProgress, 0)
        XCTAssertEqual(empty.netProgress, 0)
        XCTAssertEqual(empty.proteinProgress, 0)
        XCTAssertEqual(empty.carbsProgress, 0)
        XCTAssertEqual(empty.fiberProgress, 0)
        XCTAssertEqual(empty.intakeLine, "0 kcal")
        XCTAssertEqual(empty.fiberLine, "0 g")
    }

    func testFiberProgressUsesSummaryFiberNotFat() async {
        let store = InMemoryGoalsStore()
        store.save(
            UserGoals(
                dailyCaloriesKcal: 1800,
                targetWeightKg: nil,
                proteinGrams: 90,
                carbsGrams: 200,
                fiberGrams: 25,
                fatGrams: 60
            )
        )
        let photo = MockMealPhotoRepository(sessionUserId: user.id)
        let food = FoodItem(
            id: "f1",
            dateKey: "2026-07-13",
            meal: .lunch,
            name: "饭",
            grams: 0,
            calories: 600,
            protein: 30,
            carbs: 80,
            fat: 10,
            fiber: 12,
            note: "",
            photoPaths: [],
            photoURLs: [],
            createdAt: "",
            sourceId: nil
        )
        let vm = TodayMealsViewModel(
            user: user,
            foodRepository: MockFoodItemRepository(
                sessionUserId: user.id,
                seed: [food],
                photoRepository: photo
            ),
            photoRepository: photo,
            analyzeAPI: MockAnalyzeAPIClient(),
            goalsStore: store,
            dateKey: "2026-07-13"
        )
        await vm.load()
        XCTAssertEqual(vm.goalsProgress.fiberG, 12)
        XCTAssertEqual(vm.goalsProgress.fiberLine, "12 / 25 g")
        XCTAssertEqual(vm.goalsProgress.fiberProgress, 12.0 / 25.0, accuracy: 0.0001)
        XCTAssertEqual(vm.goalsProgress.proteinLine, "30 / 90 g")
        // Food fat exists; goals.fatGrams may exist but is not home progress.
        XCTAssertEqual(vm.summary.fat, 10)
        XCTAssertEqual(vm.goals.fatGrams, 60)
        XCTAssertEqual(vm.goalsProgress.fiberG, 12)
        XCTAssertNotEqual(vm.goals.fiberGrams, vm.goals.fatGrams)
    }

    func testTodayMealsViewModelReloadsGoalsForOverview() async {
        let store = InMemoryGoalsStore()
        store.save(
            UserGoals(
                dailyCaloriesKcal: 1800,
                targetWeightKg: nil,
                proteinGrams: 90,
                carbsGrams: nil,
                fiberGrams: nil,
                fatGrams: nil
            )
        )
        let photo = MockMealPhotoRepository(sessionUserId: user.id)
        let food = FoodItem(
            id: "f1",
            dateKey: "2026-07-13",
            meal: .lunch,
            name: "饭",
            grams: 0,
            calories: 600,
            protein: 30,
            carbs: 80,
            fat: 10,
            fiber: 0,
            note: "",
            photoPaths: [],
            photoURLs: [],
            createdAt: "",
            sourceId: nil
        )
        let vm = TodayMealsViewModel(
            user: user,
            foodRepository: MockFoodItemRepository(
                sessionUserId: user.id,
                seed: [food],
                photoRepository: photo
            ),
            photoRepository: photo,
            analyzeAPI: MockAnalyzeAPIClient(),
            goalsStore: store,
            dateKey: "2026-07-13"
        )
        await vm.load()
        XCTAssertEqual(vm.goals.dailyCaloriesKcal, 1800)
        XCTAssertEqual(vm.goalsProgress.intakeLine, "600 / 1800 kcal")
        XCTAssertEqual(vm.goalsProgress.proteinLine, "30 / 90 g")

        // No goals: safe display
        store.save(.empty)
        vm.reloadGoals()
        XCTAssertEqual(vm.goalsProgress.intakeLine, "600 kcal")
        XCTAssertFalse(vm.goals.hasAnyGoal)
    }

    func testSettingsSaveUpdatesSharedStoreForOverview() async {
        let store = InMemoryGoalsStore()
        let photo = MockMealPhotoRepository(sessionUserId: user.id)
        let vm = TodayMealsViewModel(
            user: user,
            foodRepository: MockFoodItemRepository(sessionUserId: user.id, photoRepository: photo),
            photoRepository: photo,
            analyzeAPI: MockAnalyzeAPIClient(),
            goalsStore: store,
            dateKey: "2026-07-13"
        )
        let settings = vm.makeSettingsViewModel(onSignOut: {})
        settings.draftCalories = "2200"
        settings.draftProtein = "130"
        settings.draftFiber = "28"
        XCTAssertTrue(settings.saveGoals())
        vm.reloadGoals()
        XCTAssertEqual(vm.goals.dailyCaloriesKcal, 2200)
        XCTAssertEqual(vm.goals.proteinGrams, 130)
        XCTAssertEqual(vm.goals.fiberGrams, 28)
        XCTAssertEqual(vm.goalsProgress.fiberLine, "0 / 28 g")
    }
}
