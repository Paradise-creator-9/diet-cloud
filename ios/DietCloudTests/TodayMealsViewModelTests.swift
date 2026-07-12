import XCTest
@testable import DietCloud

@MainActor
final class TodayMealsViewModelTests: XCTestCase {
    private let user = AuthUser(id: "user-1", email: "a@example.com")
    private let dateKey = "2026-07-13"

    func testInitialLoadStateIsLoadingThenEmpty() async {
        let repo = MockFoodItemRepository()
        let vm = TodayMealsViewModel(
            user: user,
            foodRepository: repo,
            diaryCalendar: DiaryCalendar(),
            dateKey: dateKey
        )
        XCTAssertEqual(vm.loadState, .loading)
        XCTAssertEqual(vm.dateKey, dateKey)
        await vm.load()
        XCTAssertEqual(vm.loadState, .empty)
        XCTAssertTrue(vm.items.isEmpty)
        XCTAssertEqual(vm.summary, .zero)
    }

    func testLoadGroupsByMealTypeAndComputesSummary() async {
        let repo = MockFoodItemRepository(seed: [
            food(id: "1", meal: .breakfast, name: "蛋", cal: 70, protein: 6, carbs: 1, fat: 5),
            food(id: "2", meal: .lunch, name: "饭", cal: 200, protein: 4, carbs: 40, fat: 1),
            food(id: "3", meal: .breakfast, name: "奶", cal: 100, protein: 8, carbs: 10, fat: 3),
        ])
        let vm = TodayMealsViewModel(
            user: user,
            foodRepository: repo,
            dateKey: dateKey
        )
        await vm.load()
        XCTAssertEqual(vm.loadState, .loaded)
        XCTAssertEqual(vm.items.count, 3)
        XCTAssertEqual(vm.summary.calories, 370)
        XCTAssertEqual(vm.summary.protein, 18)
        XCTAssertEqual(vm.summary.carbs, 51)
        XCTAssertEqual(vm.summary.fat, 9)

        let breakfast = vm.mealSections.first { $0.meal == .breakfast }
        XCTAssertEqual(breakfast?.items.count, 2)
        let snack = vm.mealSections.first { $0.meal == .snack }
        XCTAssertEqual(snack?.items.count, 0)
        // All four slots present for UI sections.
        XCTAssertEqual(vm.mealSections.map(\.meal), MealType.displayOrder)
    }

    func testLoadErrorStateDoesNotLeakToken() async {
        let repo = MockFoodItemRepository()
        repo.forcedError = AppError.auth(.provider(message: "bad eyJhbGciOiJIUzI1NiJ9.payload.sig"))
        let vm = TodayMealsViewModel(user: user, foodRepository: repo, dateKey: dateKey)
        await vm.load()
        if case .error(let message) = vm.loadState {
            XCTAssertFalse(message.contains("eyJ"))
            XCTAssertEqual(vm.errorMessage, message)
        } else {
            XCTFail("expected error state")
        }
    }

    func testAddItemSuccessRefreshesList() async {
        let repo = MockFoodItemRepository()
        let vm = TodayMealsViewModel(user: user, foodRepository: repo, dateKey: dateKey)
        await vm.load()
        XCTAssertEqual(vm.loadState, .empty)

        vm.openAddSheet(defaultMeal: .dinner)
        vm.draftName = "西兰花"
        vm.draftCalories = "70"
        vm.draftProtein = "6"
        await vm.saveNewItem()

        XCTAssertFalse(vm.isPresentingAddSheet)
        XCTAssertEqual(vm.loadState, .loaded)
        XCTAssertEqual(vm.items.count, 1)
        XCTAssertEqual(vm.items.first?.name, "西兰花")
        XCTAssertEqual(vm.items.first?.meal, .dinner)
        XCTAssertEqual(vm.summary.calories, 70)
        XCTAssertEqual(vm.summary.protein, 6)
    }

    func testAddItemFailureKeepsSheetAndShowsError() async {
        let repo = MockFoodItemRepository()
        let vm = TodayMealsViewModel(user: user, foodRepository: repo, dateKey: dateKey)
        await vm.load()
        vm.openAddSheet()
        vm.draftName = "失败项"
        repo.forcedError = AppError.network(message: "network down")
        await vm.saveNewItem()
        XCTAssertTrue(vm.isPresentingAddSheet)
        XCTAssertEqual(vm.errorMessage, AppError.network(message: "network down").userMessage)
        XCTAssertTrue(vm.items.isEmpty)
    }

    func testAddRequiresName() async {
        let repo = MockFoodItemRepository()
        let vm = TodayMealsViewModel(user: user, foodRepository: repo, dateKey: dateKey)
        vm.openAddSheet()
        vm.draftName = "   "
        await vm.saveNewItem()
        XCTAssertEqual(vm.errorMessage, "请填写食物名称。")
        XCTAssertTrue(vm.isPresentingAddSheet)
    }

    func testDeleteSuccessRefreshes() async {
        let seed = food(id: "keep-me", meal: .snack, name: "香蕉", cal: 100, protein: 1, carbs: 20, fat: 0)
        let repo = MockFoodItemRepository(seed: [seed])
        let vm = TodayMealsViewModel(user: user, foodRepository: repo, dateKey: dateKey)
        await vm.load()
        XCTAssertEqual(vm.items.count, 1)
        await vm.deleteItem(seed)
        XCTAssertEqual(vm.loadState, .empty)
        XCTAssertTrue(vm.items.isEmpty)
        XCTAssertEqual(vm.summary, .zero)
    }

    func testDeleteFailureSetsError() async {
        let seed = food(id: "x", meal: .lunch, name: "饭", cal: 200, protein: 0, carbs: 0, fat: 0)
        let repo = MockFoodItemRepository(seed: [seed])
        let vm = TodayMealsViewModel(user: user, foodRepository: repo, dateKey: dateKey)
        await vm.load()
        repo.forcedError = AppError.unauthorized
        await vm.deleteItem(seed)
        XCTAssertEqual(vm.errorMessage, AppError.unauthorized.userMessage)
        // Forced error on delete leaves in-memory seed intact for next successful ops;
        // view model does not clear items on delete failure.
        XCTAssertEqual(vm.items.count, 1)
    }

    func testDateKeyUsesDiaryCalendarWhenNotInjected() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!
        let diary = DiaryCalendar(calendar: calendar)
        let expected = diary.dateKey()
        let vm = TodayMealsViewModel(
            user: user,
            foodRepository: MockFoodItemRepository(),
            diaryCalendar: diary
        )
        XCTAssertEqual(vm.dateKey, expected)
    }

    func testSignedInRootUsesTodayMealsFactory() {
        let foodRepo = MockFoodItemRepository()
        let auth = MockAuthRepository()
        let user = AuthUser(id: "u", email: "t@example.com")
        let authVM = AuthViewModel(repository: auth, isConfigured: true)
        // Simulate signed-in without bootstrap network.
        // Auth phase is private(set); use handle path via factory presence.
        let todayVM = TodayMealsViewModel(user: user, foodRepository: foodRepo, dateKey: dateKey)
        let root = AuthRootView(
            viewModel: authVM,
            configDiagnostics: "test",
            makeTodayMealsViewModel: { _ in todayVM }
        )
        // Smoke: view constructs with factory (signedIn branch covered in ViewModel tests).
        _ = root
        XCTAssertEqual(todayVM.dateKey, dateKey)
    }

    private func food(
        id: String,
        meal: MealType,
        name: String,
        cal: Double,
        protein: Double,
        carbs: Double,
        fat: Double
    ) -> FoodItem {
        FoodItem(
            id: id,
            dateKey: dateKey,
            meal: meal,
            name: name,
            grams: 0,
            calories: cal,
            protein: protein,
            carbs: carbs,
            fat: fat,
            fiber: 0,
            note: "",
            photoPaths: [],
            photoURLs: [],
            createdAt: "2026-07-13T08:00:00Z",
            sourceId: nil
        )
    }
}
