import XCTest
@testable import DietCloud

@MainActor
final class TrendsViewModelTests: XCTestCase {
    private let userId = "11111111-1111-1111-1111-111111111111"
    private let calendar = DiaryCalendar.tokyo()
    /// Anchor "now" so windows are stable.
    private let now = DiaryCalendar.tokyo().date(fromDateKey: "2026-07-13")!

    func testLoadLoadedStateWithData() async {
        let food = MockFoodItemRepository(sessionUserId: userId, seed: [
            makeFood(date: "2026-07-13", cal: 1800, protein: 110, fiber: 28)
        ])
        let vm = makeVM(food: food)
        await vm.load()
        guard case .loaded(let snap) = vm.loadState else {
            return XCTFail("expected loaded, got \(vm.loadState)")
        }
        XCTAssertEqual(snap.summary.foodRecordedDays, 1)
        XCTAssertEqual(food.fetchBetweenCallCount, 1)
        XCTAssertEqual(food.lastFetchBetween?.0, "2026-07-07")
        XCTAssertEqual(food.lastFetchBetween?.1, "2026-07-13")
    }

    func testEmptyWhenNoDataInRange() async {
        let vm = makeVM()
        await vm.load()
        guard case .empty(let snap) = vm.loadState else {
            return XCTFail("expected empty, got \(vm.loadState)")
        }
        XCTAssertFalse(snap.hasAnyData)
        XCTAssertEqual(snap.dateKeys.count, 7)
    }

    func testPartialWhenOneSourceFailsButOthersHaveData() async {
        let food = MockFoodItemRepository(sessionUserId: userId, seed: [
            makeFood(date: "2026-07-12", cal: 1500, protein: 80, fiber: 20)
        ])
        let body = MockBodyMetricsRepository(sessionUserId: userId)
        body.forcedError = AppError.network(message: "body down")
        let vm = makeVM(food: food, body: body)
        await vm.load()
        guard case .partial(let snap, let failed, _) = vm.loadState else {
            return XCTFail("expected partial, got \(vm.loadState)")
        }
        XCTAssertTrue(failed.contains("身体"))
        XCTAssertEqual(snap.summary.foodRecordedDays, 1)
    }

    func testErrorWhenAllSourcesFail() async {
        let food = MockFoodItemRepository(sessionUserId: userId)
        food.forcedError = AppError.network(message: "food fail")
        let body = MockBodyMetricsRepository(sessionUserId: userId)
        body.forcedError = AppError.network(message: "body fail")
        let daily = MockDailyActivityRepository(sessionUserId: userId)
        daily.forcedError = AppError.network(message: "daily fail")
        let exercise = MockExerciseActivityRepository(sessionUserId: userId)
        exercise.forcedError = AppError.network(message: "ex fail")
        let vm = makeVM(food: food, body: body, daily: daily, exercise: exercise)
        await vm.load()
        guard case .error(let message) = vm.loadState else {
            return XCTFail("expected error, got \(vm.loadState)")
        }
        XCTAssertFalse(message.isEmpty)
    }

    func testRetryAfterErrorSucceeds() async {
        let food = MockFoodItemRepository(sessionUserId: userId)
        food.forcedError = AppError.network(message: "temp")
        let body = MockBodyMetricsRepository(sessionUserId: userId)
        body.forcedError = AppError.network(message: "temp")
        let daily = MockDailyActivityRepository(sessionUserId: userId)
        daily.forcedError = AppError.network(message: "temp")
        let exercise = MockExerciseActivityRepository(sessionUserId: userId)
        exercise.forcedError = AppError.network(message: "temp")
        let vm = makeVM(food: food, body: body, daily: daily, exercise: exercise)
        await vm.load()
        guard case .error = vm.loadState else {
            return XCTFail("expected error first")
        }

        food.forcedError = nil
        body.forcedError = nil
        daily.forcedError = nil
        exercise.forcedError = nil
        await vm.retry()
        guard case .empty = vm.loadState else {
            return XCTFail("expected empty after successful retry with no data, got \(vm.loadState)")
        }
    }

    func testRetryDoesNotClearLoadedSnapshotDuringReload() async {
        let food = MockFoodItemRepository(sessionUserId: userId, seed: [
            makeFood(date: "2026-07-13", cal: 1800, protein: 110, fiber: 28)
        ])
        let body = MockBodyMetricsRepository(sessionUserId: userId)
        let vm = makeVM(food: food, body: body)
        await vm.load()
        guard case .loaded = vm.loadState else {
            return XCTFail("expected loaded first")
        }

        // Slow/error path on body while food still available → partial, never full-screen loading wipe.
        body.forcedError = AppError.network(message: "body fail")
        await vm.retry()
        switch vm.loadState {
        case .partial(let snap, let failed, let message):
            XCTAssertTrue(failed.contains("身体"))
            XCTAssertTrue(message.contains("身体"))
            XCTAssertEqual(snap.summary.foodRecordedDays, 1)
        case .loading:
            XCTFail("retry must not blank to loading when a prior snapshot exists")
        default:
            XCTFail("expected partial after body failure, got \(vm.loadState)")
        }
    }

    func testSwitchRangeTo30DaysReloadsWithNewBounds() async {
        let food = MockFoodItemRepository(sessionUserId: userId, seed: [
            makeFood(date: "2026-07-01", cal: 1000, protein: 40, fiber: 10),
            makeFood(date: "2026-07-13", cal: 2000, protein: 100, fiber: 25)
        ])
        let vm = makeVM(food: food)
        await vm.load()
        XCTAssertEqual(food.lastFetchBetween?.0, "2026-07-07")

        await vm.selectRange(.days30)
        XCTAssertEqual(vm.range, .days30)
        XCTAssertEqual(food.lastFetchBetween?.0, "2026-06-14")
        XCTAssertEqual(food.lastFetchBetween?.1, "2026-07-13")
        guard case .loaded(let snap) = vm.loadState else {
            return XCTFail("expected loaded for 30-day window, got \(vm.loadState)")
        }
        XCTAssertEqual(snap.dateKeys.count, 30)
        XCTAssertEqual(snap.summary.foodRecordedDays, 2)
    }

    func testGoalMetNotConfiguredInSnapshot() async {
        let food = MockFoodItemRepository(sessionUserId: userId, seed: [
            makeFood(date: "2026-07-13", cal: 1800, protein: 90, fiber: 20)
        ])
        let store = InMemoryGoalsStore(goals: .empty)
        let vm = makeVM(food: food, goals: store)
        await vm.load()
        guard case .loaded(let snap) = vm.loadState else {
            return XCTFail("expected loaded")
        }
        XCTAssertEqual(snap.summary.goalMet, .notConfigured)
    }

    func testGoalMetConfiguredCountsBandAndMacros() async {
        let food = MockFoodItemRepository(sessionUserId: userId, seed: [
            makeFood(date: "2026-07-12", cal: 2000, protein: 120, fiber: 30),
            makeFood(date: "2026-07-13", cal: 1000, protein: 120, fiber: 30) // calories out of band
        ])
        let store = InMemoryGoalsStore(goals: UserGoals(
            dailyCaloriesKcal: 2000,
            targetWeightKg: nil,
            proteinGrams: 100,
            carbsGrams: nil,
            fiberGrams: 25,
            fatGrams: nil
        ))
        let vm = makeVM(food: food, goals: store)
        await vm.load()
        guard case .loaded(let snap) = vm.loadState else {
            return XCTFail("expected loaded")
        }
        XCTAssertEqual(snap.summary.goalMet, .configured(metDays: 1))
    }

    // MARK: - Helpers

    private func makeVM(
        food: MockFoodItemRepository? = nil,
        body: MockBodyMetricsRepository? = nil,
        daily: MockDailyActivityRepository? = nil,
        exercise: MockExerciseActivityRepository? = nil,
        goals: GoalsStoring? = nil
    ) -> TrendsViewModel {
        TrendsViewModel(
            foodRepository: food ?? MockFoodItemRepository(sessionUserId: userId),
            bodyRepository: body ?? MockBodyMetricsRepository(sessionUserId: userId),
            dailyActivityRepository: daily ?? MockDailyActivityRepository(sessionUserId: userId),
            exerciseRepository: exercise ?? MockExerciseActivityRepository(sessionUserId: userId),
            goalsStore: goals ?? InMemoryGoalsStore(),
            diaryCalendar: calendar,
            nowProvider: { self.now }
        )
    }

    private func makeFood(date: String, cal: Double, protein: Double, fiber: Double) -> FoodItem {
        FoodItem(
            id: UUID().uuidString,
            dateKey: date,
            meal: .dinner,
            name: "meal",
            grams: 0,
            calories: cal,
            protein: protein,
            carbs: 50,
            fat: 10,
            fiber: fiber,
            note: "",
            photoPaths: [],
            photoURLs: [],
            createdAt: "\(date)T12:00:00Z",
            sourceId: nil
        )
    }
}
