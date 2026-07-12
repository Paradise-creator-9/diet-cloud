import XCTest
@testable import DietCloud

final class FavoriteFoodValidationTests: XCTestCase {
    func testEmptyNameRejected() {
        let (food, message) = FavoriteFoodValidation.validate(
            id: nil,
            nameText: "  ",
            meal: .lunch,
            gramsText: "100",
            caloriesText: "200",
            proteinText: "10",
            carbsText: "20",
            fatText: "5",
            fiberText: "3",
            noteText: ""
        )
        XCTAssertNil(food)
        XCTAssertEqual(message, "请填写食物名称。")
    }

    func testEmptyNumbersBecomeZero() {
        let (food, message) = FavoriteFoodValidation.validate(
            id: "f1",
            nameText: "香蕉",
            meal: .snack,
            gramsText: "",
            caloriesText: "",
            proteinText: "",
            carbsText: "",
            fatText: "",
            fiberText: "",
            noteText: "  零食  "
        )
        XCTAssertNil(message)
        XCTAssertEqual(food?.id, "f1")
        XCTAssertEqual(food?.name, "香蕉")
        XCTAssertEqual(food?.meal, .snack)
        XCTAssertEqual(food?.grams, 0)
        XCTAssertEqual(food?.calories, 0)
        XCTAssertEqual(food?.protein, 0)
        XCTAssertEqual(food?.carbs, 0)
        XCTAssertEqual(food?.fat, 0)
        XCTAssertEqual(food?.fiber, 0)
        XCTAssertEqual(food?.note, "零食")
    }

    func testNegativeRejected() {
        let (food, message) = FavoriteFoodValidation.validate(
            id: nil,
            nameText: "鸡胸",
            meal: .lunch,
            gramsText: "100",
            caloriesText: "-1",
            proteinText: "",
            carbsText: "",
            fatText: "",
            fiberText: "",
            noteText: ""
        )
        XCTAssertNil(food)
        XCTAssertTrue((message ?? "").contains("热量") || (message ?? "").contains("负"))
    }

    func testNonNumericRejected() {
        let (food, message) = FavoriteFoodValidation.validate(
            id: nil,
            nameText: "鸡胸",
            meal: .lunch,
            gramsText: "abc",
            caloriesText: "100",
            proteinText: "",
            carbsText: "",
            fatText: "",
            fiberText: "",
            noteText: ""
        )
        XCTAssertNil(food)
        XCTAssertTrue((message ?? "").contains("份量") || (message ?? "").contains("数字"))
    }

    func testValidTemplateKeepsFiberAndMeal() {
        let (food, message) = FavoriteFoodValidation.validate(
            id: "keep-id",
            nameText: "燕麦",
            meal: .breakfast,
            gramsText: "50",
            caloriesText: "190",
            proteinText: "7",
            carbsText: "32",
            fatText: "4",
            fiberText: "5.5",
            noteText: "水煮"
        )
        XCTAssertNil(message)
        XCTAssertEqual(food?.id, "keep-id")
        XCTAssertEqual(food?.fiber, 5.5)
        XCTAssertEqual(food?.meal, .breakfast)
        XCTAssertEqual(food?.calories, 190)
    }

    func testMakeCreateWriteHasNoPhotosOrSourceId() {
        let favorite = FavoriteFood(
            name: "奶",
            meal: .breakfast,
            grams: 200,
            calories: 120,
            protein: 8,
            carbs: 10,
            fat: 4,
            fiber: 0,
            note: "低脂"
        )
        let write = favorite.makeCreateWrite(dateKey: "2026-07-13")
        XCTAssertEqual(write.dateKey, "2026-07-13")
        XCTAssertEqual(write.meal, .breakfast)
        XCTAssertEqual(write.name, "奶")
        XCTAssertEqual(write.fiber, 0)
        XCTAssertTrue(write.photoPaths.isEmpty)
        XCTAssertNil(write.sourceId)
    }

    func testFromFoodItemCopiesNutritionNotPhotos() {
        let item = FoodItem(
            id: "row-1",
            dateKey: "2026-07-13",
            meal: .dinner,
            name: "咖喱",
            grams: 300,
            calories: 500,
            protein: 20,
            carbs: 60,
            fat: 15,
            fiber: 4,
            note: "自制",
            photoPaths: ["u/2026-07-13/a.jpg"],
            photoURLs: ["https://example.com/a.jpg"],
            createdAt: "2026-07-13T12:00:00Z",
            sourceId: "manual-xyz"
        )
        let favorite = FavoriteFood.fromFoodItem(item)
        XCTAssertEqual(favorite.name, "咖喱")
        XCTAssertEqual(favorite.meal, .dinner)
        XCTAssertEqual(favorite.grams, 300)
        XCTAssertEqual(favorite.calories, 500)
        XCTAssertEqual(favorite.fiber, 4)
        XCTAssertEqual(favorite.note, "自制")
        XCTAssertNotEqual(favorite.id, item.id)
        // Template has no photo / source fields by design.
        let write = favorite.makeCreateWrite(dateKey: "2026-07-14")
        XCTAssertTrue(write.photoPaths.isEmpty)
        XCTAssertNil(write.sourceId)
        XCTAssertEqual(write.dateKey, "2026-07-14")
    }
}

final class FavoriteFoodsStoreTests: XCTestCase {
    func testDefaultEmptyTemplateList() {
        let store = InMemoryFavoriteFoodsStore()
        XCTAssertTrue(store.favorites.isEmpty)

        let suite = "dietcloud.tests.favorites.empty.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let ud = UserDefaultsFavoriteFoodsStore(defaults: defaults)
        XCTAssertTrue(ud.favorites.isEmpty)
        XCTAssertEqual(UserDefaultsFavoriteFoodsStore.storageKey, "dietcloud.favoriteFoods.v1")
    }

    func testUserDefaultsCRUDAndReload() {
        let suite = "dietcloud.tests.favorites.crud.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = UserDefaultsFavoriteFoodsStore(defaults: defaults)
        let a = FavoriteFood(id: "a", name: "香蕉", meal: .snack, grams: 100, calories: 90, protein: 1, carbs: 23, fat: 0, fiber: 2, note: "")
        let b = FavoriteFood(id: "b", name: "鸡胸", meal: .lunch, grams: 150, calories: 200, protein: 40, carbs: 0, fat: 3, fiber: 0, note: "水煮")
        store.save([a, b])
        XCTAssertEqual(store.favorites.count, 2)

        // Simulate restart: new store instance reading same defaults.
        let reloaded = UserDefaultsFavoriteFoodsStore(defaults: defaults)
        XCTAssertEqual(reloaded.favorites.count, 2)
        XCTAssertEqual(reloaded.favorites.map(\.name), ["香蕉", "鸡胸"])
        XCTAssertEqual(reloaded.favorites[1].protein, 40)
        XCTAssertEqual(reloaded.favorites[1].fiber, 0)

        // Update + delete
        var next = reloaded.favorites
        next[0] = FavoriteFood(id: "a", name: "香蕉熟", meal: .snack, grams: 120, calories: 100, protein: 1, carbs: 25, fat: 0, fiber: 3, note: "")
        next.removeAll { $0.id == "b" }
        reloaded.save(next)

        let again = UserDefaultsFavoriteFoodsStore(defaults: defaults)
        again.reload()
        XCTAssertEqual(again.favorites.count, 1)
        XCTAssertEqual(again.favorites.first?.name, "香蕉熟")
        XCTAssertEqual(again.favorites.first?.fiber, 3)
    }

    func testCorruptDataFallsBackToEmpty() {
        let suite = "dietcloud.tests.favorites.corrupt.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(Data("not-json".utf8), forKey: UserDefaultsFavoriteFoodsStore.storageKey)
        let store = UserDefaultsFavoriteFoodsStore(defaults: defaults)
        XCTAssertTrue(store.favorites.isEmpty)
        // Self-heal: corrupt key removed
        XCTAssertNil(defaults.data(forKey: UserDefaultsFavoriteFoodsStore.storageKey))

        // Wrong shape (object instead of array)
        defaults.set(Data("{\"name\":\"x\"}".utf8), forKey: UserDefaultsFavoriteFoodsStore.storageKey)
        store.reload()
        XCTAssertTrue(store.favorites.isEmpty)
        XCTAssertNil(defaults.data(forKey: UserDefaultsFavoriteFoodsStore.storageKey))
    }

    func testInMemorySaveAndLoad() {
        let store = InMemoryFavoriteFoodsStore()
        store.save([
            FavoriteFood(name: "牛奶", meal: .breakfast, calories: 120, protein: 8)
        ])
        XCTAssertEqual(store.favorites.count, 1)
        XCTAssertEqual(store.favorites.first?.name, "牛奶")
        store.reload()
        XCTAssertEqual(store.favorites.count, 1)
    }
}

@MainActor
final class FavoriteFoodsViewModelTests: XCTestCase {
    private let user = AuthUser(id: "11111111-1111-1111-1111-111111111111", email: "a@example.com")
    private let dateKey = "2026-07-13"

    private func makeVM(
        favorites: [FavoriteFood] = [],
        dateKey: String? = nil,
        seed: [FoodItem] = []
    ) -> (TodayMealsViewModel, MockFoodItemRepository, InMemoryFavoriteFoodsStore) {
        let photo = MockMealPhotoRepository(sessionUserId: user.id)
        let repo = MockFoodItemRepository(sessionUserId: user.id, seed: seed, photoRepository: photo)
        let store = InMemoryFavoriteFoodsStore(favorites: favorites)
        let vm = TodayMealsViewModel(
            user: user,
            foodRepository: repo,
            photoRepository: photo,
            analyzeAPI: MockAnalyzeAPIClient(),
            favoriteFoodsStore: store,
            dateKey: dateKey ?? self.dateKey
        )
        return (vm, repo, store)
    }

    func testQuickAddCallsCreateNotUpdateWithSelectedDateAndTemplateMeal() async {
        let favorite = FavoriteFood(
            id: "fav-1",
            name: "燕麦",
            meal: .breakfast,
            grams: 50,
            calories: 190,
            protein: 7,
            carbs: 32,
            fat: 4,
            fiber: 5,
            note: "热水"
        )
        let (vm, repo, _) = makeVM(favorites: [favorite], dateKey: "2026-07-10")
        await vm.load()
        XCTAssertEqual(vm.selectedDateKey, "2026-07-10")
        XCTAssertEqual(vm.loadState, .empty)

        await vm.quickAddFavorite(favorite)

        XCTAssertEqual(repo.createCallCount, 1)
        XCTAssertEqual(repo.updateCallCount, 0)
        XCTAssertEqual(repo.lastCreateWrite?.dateKey, "2026-07-10")
        XCTAssertEqual(repo.lastCreateWrite?.meal, .breakfast)
        XCTAssertEqual(repo.lastCreateWrite?.name, "燕麦")
        XCTAssertEqual(repo.lastCreateWrite?.calories, 190)
        XCTAssertEqual(repo.lastCreateWrite?.protein, 7)
        XCTAssertEqual(repo.lastCreateWrite?.fiber, 5)
        XCTAssertEqual(repo.lastCreateWrite?.note, "热水")
        XCTAssertTrue(repo.lastCreateWrite?.photoPaths.isEmpty == true)
        XCTAssertNil(repo.lastCreateWrite?.sourceId)
        XCTAssertEqual(vm.items.count, 1)
        XCTAssertEqual(vm.summary.calories, 190)
        XCTAssertEqual(vm.summary.fiber, 5)
        XCTAssertEqual(vm.loadState, .loaded)
        XCTAssertEqual(vm.selectedDateKey, "2026-07-10")
    }

    func testQuickAddOnHistoryDateDoesNotChangeSelectedDate() async {
        let favorite = FavoriteFood(name: "鸡蛋", meal: .lunch, calories: 70, protein: 6)
        let (vm, repo, _) = makeVM(favorites: [favorite], dateKey: "2026-07-01")
        await vm.load()
        await vm.quickAddFavorite(favorite)
        XCTAssertEqual(vm.selectedDateKey, "2026-07-01")
        XCTAssertEqual(repo.lastCreateWrite?.dateKey, "2026-07-01")
        XCTAssertEqual(repo.lastCreateWrite?.meal, .lunch)
        XCTAssertEqual(repo.lastFetchDateKey, "2026-07-01")
    }

    func testQuickAddDoesNotCopyPhotosOrSourceIdEvenIfTemplateBuiltFromItem() async {
        let item = FoodItem(
            id: "row",
            dateKey: dateKey,
            meal: .dinner,
            name: "咖喱饭",
            grams: 400,
            calories: 600,
            protein: 18,
            carbs: 80,
            fat: 20,
            fiber: 6,
            note: "外食",
            photoPaths: ["u/\(dateKey)/x.jpg"],
            photoURLs: ["https://signed.example/x"],
            createdAt: "2026-07-13T10:00:00Z",
            sourceId: "manual-keep"
        )
        let favorite = FavoriteFood.fromFoodItem(item)
        let (vm, repo, _) = makeVM(favorites: [favorite])
        await vm.load()
        await vm.quickAddFavorite(favorite)

        XCTAssertEqual(repo.createCallCount, 1)
        XCTAssertTrue(repo.lastCreateWrite?.photoPaths.isEmpty == true)
        XCTAssertNil(repo.lastCreateWrite?.sourceId)
        XCTAssertNotEqual(repo.lastCreateWrite?.sourceId, "manual-keep")
        XCTAssertEqual(vm.items.first?.photoPaths.isEmpty, true)
    }

    func testAddFoodItemToFavoritesDoesNotCallRepository() async {
        let item = FoodItem(
            id: "row-2",
            dateKey: dateKey,
            meal: .snack,
            name: "苹果",
            grams: 180,
            calories: 95,
            protein: 0.5,
            carbs: 25,
            fat: 0.3,
            fiber: 4,
            note: "红富士",
            photoPaths: ["u/p.jpg"],
            photoURLs: [],
            createdAt: "2026-07-13T11:00:00Z",
            sourceId: "src-1"
        )
        let (vm, repo, store) = makeVM(seed: [item])
        await vm.load()
        XCTAssertTrue(vm.favoriteFoods.isEmpty)

        vm.addFoodItemToFavorites(item)

        XCTAssertEqual(repo.createCallCount, 0)
        XCTAssertEqual(repo.updateCallCount, 0)
        XCTAssertEqual(vm.favoriteFoods.count, 1)
        XCTAssertEqual(store.favorites.count, 1)
        XCTAssertEqual(vm.favoriteFoods.first?.name, "苹果")
        XCTAssertEqual(vm.favoriteFoods.first?.meal, .snack)
        XCTAssertEqual(vm.favoriteFoods.first?.fiber, 4)
        XCTAssertEqual(vm.favoriteFoods.first?.note, "红富士")
        // Existing diary row unchanged
        XCTAssertEqual(vm.items.first?.id, "row-2")
        XCTAssertEqual(vm.items.first?.sourceId, "src-1")
        XCTAssertEqual(vm.items.first?.photoPaths, ["u/p.jpg"])
    }

    func testInvalidTemplateSaveDoesNotTouchStoreOrRepository() async {
        let (vm, repo, store) = makeVM()
        vm.beginAddFavoriteTemplate()
        vm.favoriteDraftName = ""
        vm.favoriteDraftCalories = "100"
        let ok = vm.saveFavoriteTemplate()
        XCTAssertFalse(ok)
        XCTAssertNotNil(vm.favoriteFormError)
        XCTAssertTrue(store.favorites.isEmpty)
        XCTAssertEqual(repo.createCallCount, 0)

        vm.favoriteDraftName = "坏数据"
        vm.favoriteDraftCalories = "-5"
        XCTAssertFalse(vm.saveFavoriteTemplate())
        XCTAssertTrue(store.favorites.isEmpty)
        XCTAssertEqual(repo.createCallCount, 0)
    }

    func testSaveFavoriteTemplateCRUDDoesNotMutateDiaryRows() async {
        let existing = FoodItem(
            id: "keep",
            dateKey: dateKey,
            meal: .lunch,
            name: "原记录",
            grams: 100,
            calories: 100,
            protein: 10,
            carbs: 10,
            fat: 1,
            fiber: 1,
            note: "",
            photoPaths: [],
            photoURLs: [],
            createdAt: "2026-07-13T09:00:00Z",
            sourceId: nil
        )
        let (vm, repo, store) = makeVM(seed: [existing])
        await vm.load()

        vm.beginAddFavoriteTemplate()
        vm.favoriteDraftName = "常吃A"
        vm.favoriteDraftMeal = .dinner
        vm.favoriteDraftCalories = "300"
        vm.favoriteDraftFiber = "8"
        XCTAssertTrue(vm.saveFavoriteTemplate())
        XCTAssertEqual(store.favorites.count, 1)
        XCTAssertEqual(vm.favoriteFoods.first?.meal, .dinner)
        XCTAssertEqual(vm.favoriteFoods.first?.fiber, 8)

        let id = vm.favoriteFoods[0].id
        vm.beginEditFavoriteTemplate(vm.favoriteFoods[0])
        vm.favoriteDraftName = "常吃B"
        vm.favoriteDraftCalories = "350"
        XCTAssertTrue(vm.saveFavoriteTemplate())
        XCTAssertEqual(vm.favoriteFoods.count, 1)
        XCTAssertEqual(vm.favoriteFoods.first?.name, "常吃B")
        XCTAssertEqual(vm.favoriteFoods.first?.id, id)

        vm.deleteFavoriteTemplate(id: id)
        XCTAssertTrue(vm.favoriteFoods.isEmpty)

        // Diary untouched
        XCTAssertEqual(repo.createCallCount, 0)
        XCTAssertEqual(repo.updateCallCount, 0)
        XCTAssertEqual(vm.items.count, 1)
        XCTAssertEqual(vm.items.first?.name, "原记录")
        XCTAssertEqual(vm.items.first?.calories, 100)
    }

    func testDuplicateQuickAddProtectedByIsMutating() async {
        final class SlowCreateRepo: FoodItemRepositoryProtocol, @unchecked Sendable {
            let inner: MockFoodItemRepository
            var gate: CheckedContinuation<Void, Never>?
            var entered = false

            init(inner: MockFoodItemRepository) { self.inner = inner }

            func fetchAll() async throws -> [FoodItem] { try await inner.fetchAll() }
            func fetchByDateKey(_ dateKey: String) async throws -> [FoodItem] {
                try await inner.fetchByDateKey(dateKey)
            }
            func fetchBetween(startDateKey: String, endDateKey: String) async throws -> [FoodItem] {
                try await inner.fetchBetween(startDateKey: startDateKey, endDateKey: endDateKey)
            }
            func fetchById(_ id: String) async throws -> FoodItem? { try await inner.fetchById(id) }
            func create(_ write: FoodItemWrite) async throws -> FoodItem {
                entered = true
                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    gate = cont
                }
                return try await inner.create(write)
            }
            func update(id: String, write: FoodItemWrite) async throws -> FoodItem {
                try await inner.update(id: id, write: write)
            }
            func delete(id: String) async throws { try await inner.delete(id: id) }
            func nutritionSummary(for items: [FoodItem]) -> DailyNutritionSummary {
                inner.nutritionSummary(for: items)
            }
        }

        let favorite = FavoriteFood(name: "重复点", meal: .snack, calories: 50)
        let photo = MockMealPhotoRepository(sessionUserId: user.id)
        let mock = MockFoodItemRepository(sessionUserId: user.id, photoRepository: photo)
        let slow = SlowCreateRepo(inner: mock)
        let store = InMemoryFavoriteFoodsStore(favorites: [favorite])
        let slowVM = TodayMealsViewModel(
            user: user,
            foodRepository: slow,
            photoRepository: photo,
            analyzeAPI: MockAnalyzeAPIClient(),
            favoriteFoodsStore: store,
            dateKey: dateKey
        )
        await slowVM.load()

        async let first: Void = slowVM.quickAddFavorite(favorite)
        for _ in 0..<100 where !slow.entered {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(slow.entered)
        XCTAssertTrue(slowVM.isMutating)

        await slowVM.quickAddFavorite(favorite)
        XCTAssertEqual(mock.createCallCount, 0)

        slow.gate?.resume()
        slow.gate = nil
        await first

        XCTAssertEqual(mock.createCallCount, 1)
        XCTAssertFalse(slowVM.isMutating)
    }

    func testQuickAddFailureShowsChineseErrorWithoutLeavingPartialState() async {
        let favorite = FavoriteFood(name: "失败项", meal: .lunch, calories: 100)
        let (vm, repo, _) = makeVM(favorites: [favorite])
        repo.forcedError = AppError.network(message: "network down")
        await vm.load()
        await vm.quickAddFavorite(favorite)
        XCTAssertEqual(repo.createCallCount, 0)
        XCTAssertEqual(vm.errorMessage, AppError.network(message: "network down").userMessage)
        XCTAssertFalse((vm.errorMessage ?? "").contains("Exception"))
        XCTAssertTrue(vm.items.isEmpty)
    }

    func testQuickAddEmptyNameDoesNotCallRepository() async {
        let favorite = FavoriteFood(name: "   ", meal: .breakfast, calories: 10)
        let (vm, repo, _) = makeVM(favorites: [favorite])
        await vm.load()
        await vm.quickAddFavorite(favorite)
        XCTAssertEqual(repo.createCallCount, 0)
        XCTAssertEqual(repo.updateCallCount, 0)
        XCTAssertEqual(vm.errorMessage, "请填写食物名称。")
        XCTAssertFalse(vm.isMutating)
    }

    func testQuickAddNegativeNutrientDoesNotCallRepository() async {
        let favorite = FavoriteFood(name: "坏", meal: .lunch, calories: -5)
        let (vm, repo, _) = makeVM(favorites: [favorite])
        await vm.load()
        await vm.quickAddFavorite(favorite)
        XCTAssertEqual(repo.createCallCount, 0)
        XCTAssertEqual(repo.updateCallCount, 0)
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertTrue((vm.errorMessage ?? "").contains("无效") || (vm.errorMessage ?? "").contains("管理"))
    }
}
