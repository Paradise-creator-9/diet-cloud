import XCTest
@testable import DietCloud

final class UserGoalsValidationTests: XCTestCase {
    func testValidGoalsSave() {
        let (goals, error) = UserGoalsValidation.validate(
            caloriesText: "2000",
            weightText: "70",
            proteinText: "120",
            carbsText: "200",
            fatText: "60"
        )
        XCTAssertNil(error)
        XCTAssertEqual(goals?.dailyCaloriesKcal, 2000)
        XCTAssertEqual(goals?.targetWeightKg, 70)
        XCTAssertEqual(goals?.proteinGrams, 120)
        XCTAssertEqual(goals?.carbsGrams, 200)
        XCTAssertEqual(goals?.fatGrams, 60)
    }

    func testEmptyFieldsClearGoals() {
        let (goals, error) = UserGoalsValidation.validate(
            caloriesText: "",
            weightText: "",
            proteinText: "",
            carbsText: "",
            fatText: ""
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
            fatText: ""
        )
        XCTAssertNil(g1)
        XCTAssertTrue((zeroMsg ?? "").contains("热量") || (zeroMsg ?? "").contains("大于"))

        let (g2, negMsg) = UserGoalsValidation.validate(
            caloriesText: "-100",
            weightText: "",
            proteinText: "",
            carbsText: "",
            fatText: ""
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
            fatText: ""
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
            fatText: ""
        )
        XCTAssertNil(goals)
        XCTAssertTrue((message ?? "").contains("蛋白质") || (message ?? "").contains("负"))
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
            fatGrams: 50
        )
        store.save(goals)
        XCTAssertEqual(store.goals.dailyCaloriesKcal, 1800)
        XCTAssertEqual(store.goals.targetWeightKg, 68)
        XCTAssertNil(store.goals.carbsGrams)
    }

    func testUserDefaultsRoundTrip() {
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
                fatGrams: 55
            )
        )
        let reloaded = UserDefaultsGoalsStore(defaults: defaults)
        XCTAssertEqual(reloaded.goals.dailyCaloriesKcal, 2100)
        XCTAssertEqual(reloaded.goals.targetWeightKg, 72.5)
        XCTAssertEqual(reloaded.goals.proteinGrams, 110)
    }
}

@MainActor
final class SettingsViewModelTests: XCTestCase {
    private let user = AuthUser(id: "11111111-1111-1111-1111-111111111111", email: "user@example.com")

    func testSaveGoalsPersistsAndRejectsInvalid() {
        let store = InMemoryGoalsStore()
        var signedOut = false
        let vm = SettingsViewModel(user: user, goalsStore: store, onSignOut: { signedOut = true })
        vm.draftCalories = "2000"
        vm.draftWeight = "70"
        vm.draftProtein = "100"
        vm.draftCarbs = "200"
        vm.draftFat = "60"
        XCTAssertTrue(vm.saveGoals())
        XCTAssertEqual(store.goals.dailyCaloriesKcal, 2000)
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
        let vm = SettingsViewModel(user: user, goalsStore: store, onSignOut: { signedOut = true })
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
            fatG: 20,
            goals: UserGoals(
                dailyCaloriesKcal: 2000,
                targetWeightKg: 70,
                proteinGrams: 120,
                carbsGrams: 200,
                fatGrams: 60
            )
        )
        XCTAssertEqual(withGoals.intakeLine, "500 / 2000 kcal")
        XCTAssertEqual(withGoals.netLine, "300 / 2000 kcal")
        XCTAssertEqual(withGoals.proteinLine, "40 / 120 g")
        XCTAssertEqual(withGoals.intakeProgress, 0.25, accuracy: 0.0001)
        XCTAssertEqual(withGoals.netProgress, 0.15, accuracy: 0.0001)
        XCTAssertEqual(withGoals.proteinProgress, 40.0 / 120.0, accuracy: 0.0001)

        let without = GoalsProgress(
            intakeKcal: 500,
            netKcal: 300,
            proteinG: 40,
            carbsG: 50,
            fatG: 20,
            goals: .empty
        )
        XCTAssertEqual(without.intakeLine, "500 kcal")
        XCTAssertEqual(without.netLine, "300 kcal")
        XCTAssertEqual(without.proteinLine, "40 g")
        XCTAssertFalse(without.goals.hasAnyGoal)
        XCTAssertEqual(without.intakeProgress, 0)
        XCTAssertEqual(without.netProgress, 0)
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
            fatG: 10,
            goals: UserGoals(
                dailyCaloriesKcal: 2000,
                targetWeightKg: nil,
                proteinGrams: 100,
                carbsGrams: nil,
                fatGrams: nil
            )
        )
        XCTAssertEqual(over.intakeProgress, 1)
        XCTAssertEqual(over.netProgress, 0) // negative net → 0
        XCTAssertEqual(over.proteinProgress, 1)
        XCTAssertTrue(over.isOverGoal(current: 2500, goal: 2000))
        XCTAssertFalse(over.isOverGoal(current: 100, goal: 2000))
    }

    func testEmptyGoalsProgressDoesNotCrash() {
        let empty = GoalsProgress(
            intakeKcal: 0,
            netKcal: 0,
            proteinG: 0,
            carbsG: 0,
            fatG: 0,
            goals: .empty
        )
        XCTAssertEqual(empty.intakeProgress, 0)
        XCTAssertEqual(empty.netProgress, 0)
        XCTAssertEqual(empty.proteinProgress, 0)
        XCTAssertEqual(empty.intakeLine, "0 kcal")
    }

    func testTodayMealsViewModelReloadsGoalsForOverview() async {
        let store = InMemoryGoalsStore()
        store.save(
            UserGoals(
                dailyCaloriesKcal: 1800,
                targetWeightKg: nil,
                proteinGrams: 90,
                carbsGrams: nil,
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
        XCTAssertTrue(settings.saveGoals())
        vm.reloadGoals()
        XCTAssertEqual(vm.goals.dailyCaloriesKcal, 2200)
        XCTAssertEqual(vm.goals.proteinGrams, 130)
    }
}
