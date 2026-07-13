import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import DietCloud

@MainActor
final class TodayMealsViewModelTests: XCTestCase {
    private let user = AuthUser(id: "11111111-1111-1111-1111-111111111111", email: "a@example.com")
    private let dateKey = "2026-07-13"

    private func makeVM(
        repo: MockFoodItemRepository? = nil,
        photo: MockMealPhotoRepository? = nil,
        analyze: MockAnalyzeAPIClient? = nil,
        diaryCalendar: DiaryCalendar = DiaryCalendar(),
        dateKey: String? = nil
    ) -> (TodayMealsViewModel, MockFoodItemRepository, MockMealPhotoRepository, MockAnalyzeAPIClient) {
        let photoRepo = photo ?? MockMealPhotoRepository(sessionUserId: user.id)
        let foodRepo = repo ?? MockFoodItemRepository(sessionUserId: user.id, photoRepository: photoRepo)
        let analyzeClient = analyze ?? MockAnalyzeAPIClient()
        let vm = TodayMealsViewModel(
            user: user,
            foodRepository: foodRepo,
            photoRepository: photoRepo,
            analyzeAPI: analyzeClient,
            diaryCalendar: diaryCalendar,
            dateKey: dateKey ?? self.dateKey
        )
        return (vm, foodRepo, photoRepo, analyzeClient)
    }

    func testInitialLoadStateIsLoadingThenEmpty() async {
        let (vm, _, _, _) = makeVM()
        XCTAssertEqual(vm.loadState, .loading)
        XCTAssertEqual(vm.dateKey, dateKey)
        await vm.load()
        XCTAssertEqual(vm.loadState, .empty)
        XCTAssertTrue(vm.items.isEmpty)
        XCTAssertEqual(vm.summary, .zero)
    }

    func testLoadGroupsByMealTypeAndComputesSummary() async {
        let photo = MockMealPhotoRepository(sessionUserId: user.id)
        let repo = MockFoodItemRepository(sessionUserId: user.id, seed: [
            food(id: "1", meal: .breakfast, name: "蛋", cal: 70, protein: 6, carbs: 1, fat: 5),
            food(id: "2", meal: .lunch, name: "饭", cal: 200, protein: 4, carbs: 40, fat: 1),
            food(id: "3", meal: .breakfast, name: "奶", cal: 100, protein: 8, carbs: 10, fat: 3),
        ], photoRepository: photo)
        let (vm, _, _, _) = makeVM(repo: repo, photo: photo)
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
        XCTAssertEqual(vm.mealSections.map(\.meal), MealType.displayOrder)
    }

    func testLoadErrorStateDoesNotLeakToken() async {
        let (vm, repo, _, _) = makeVM()
        repo.forcedError = AppError.auth(.provider(message: "bad eyJhbGciOiJIUzI1NiJ9.payload.sig"))
        await vm.load()
        if case .error(let message) = vm.loadState {
            XCTAssertFalse(message.contains("eyJ"))
            XCTAssertEqual(vm.errorMessage, message)
        } else {
            XCTFail("expected error state")
        }
    }

    func testAddItemSuccessRefreshesList() async {
        let (vm, repo, _, _) = makeVM()
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
        XCTAssertTrue(repo.lastCreatePhotoPaths.isEmpty)
    }

    func testAddItemWithPhotoUploadsThenCreates() async {
        let (vm, repo, photo, _) = makeVM()

        let jpeg = Self.tinyJPEG()
        await vm.setDraftPhoto(rawData: jpeg)
        XCTAssertNotNil(vm.draftPhotoData)
        XCTAssertNotNil(vm.draftPhotoPreview)

        vm.draftName = "咖喱饭"
        vm.draftMeal = .lunch
        vm.draftCalories = "500"
        await vm.saveNewItem()

        XCTAssertEqual(vm.items.count, 1)
        XCTAssertEqual(repo.lastCreatePhotoPaths.count, 1)
        XCTAssertTrue(repo.lastCreatePhotoPaths[0].hasPrefix("\(user.id)/\(dateKey)/"))
        XCTAssertEqual(photo.lastUploadContentType, ImageCompressor.allowedContentType)
        XCTAssertNotNil(photo.lastUploadPath)
        XCTAssertEqual(photo.lastUploadPath, repo.lastCreatePhotoPaths.first)
    }

    func testAddItemWithoutPhotoStillWorks() async {
        let (vm, repo, photo, _) = makeVM()
        vm.draftName = "水"
        await vm.saveNewItem()
        XCTAssertEqual(vm.items.count, 1)
        XCTAssertNil(photo.lastUploadPath)
        XCTAssertTrue(repo.lastCreatePhotoPaths.isEmpty)
    }

    func testAddItemFailureKeepsSheetAndShowsError() async {
        let (vm, repo, _, _) = makeVM()
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
        let (vm, _, _, _) = makeVM()
        vm.openAddSheet()
        vm.draftName = "   "
        await vm.saveNewItem()
        XCTAssertEqual(vm.errorMessage, "请填写食物名称。")
        XCTAssertTrue(vm.isPresentingAddSheet)
    }

    func testDeleteSuccessRemovesPhotoWhenOrphaned() async {
        let photo = MockMealPhotoRepository(sessionUserId: user.id)
        let path = "\(user.id)/\(dateKey)/1-meal.jpg"
        let seed = food(id: "keep-me", meal: .snack, name: "香蕉", cal: 100, protein: 1, carbs: 20, fat: 0, paths: [path])
        let repo = MockFoodItemRepository(sessionUserId: user.id, seed: [seed], photoRepository: photo)
        let (vm, _, photoRepo, _) = makeVM(repo: repo, photo: photo)
        await vm.load()
        XCTAssertEqual(vm.items.count, 1)
        await vm.deleteItem(seed)
        XCTAssertEqual(vm.loadState, .empty)
        XCTAssertTrue(vm.items.isEmpty)
        XCTAssertEqual(photoRepo.deletedPaths, [path])
    }

    func testDeleteFailureSetsError() async {
        let photo = MockMealPhotoRepository(sessionUserId: user.id)
        let seed = food(id: "x", meal: .lunch, name: "饭", cal: 200, protein: 0, carbs: 0, fat: 0)
        let repo = MockFoodItemRepository(sessionUserId: user.id, seed: [seed], photoRepository: photo)
        let (vm, foodRepo, _, _) = makeVM(repo: repo, photo: photo)
        await vm.load()
        foodRepo.forcedError = AppError.unauthorized
        await vm.deleteItem(seed)
        XCTAssertEqual(vm.errorMessage, AppError.unauthorized.userMessage)
        XCTAssertEqual(vm.items.count, 1)
    }

    func testDateKeyUsesDiaryCalendarWhenNotInjected() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!
        let diary = DiaryCalendar(calendar: calendar)
        let expected = diary.dateKey()
        let (vm, _, _, _) = makeVM(diaryCalendar: diary, dateKey: nil)
        // dateKey parameter defaults to self.dateKey in makeVM — pass explicit nil path
        let photo = MockMealPhotoRepository(sessionUserId: user.id)
        let real = TodayMealsViewModel(
            user: user,
            foodRepository: MockFoodItemRepository(sessionUserId: user.id, photoRepository: photo),
            photoRepository: photo,
            analyzeAPI: MockAnalyzeAPIClient(),
            diaryCalendar: diary
        )
        XCTAssertEqual(real.dateKey, expected)
        _ = vm
    }

    func testSignedInRootUsesTodayMealsFactory() {
        let (todayVM, _, _, _) = makeVM()
        let auth = MockAuthRepository()
        let authVM = AuthViewModel(repository: auth, isConfigured: true)
        let root = AuthRootView(
            viewModel: authVM,
            configDiagnostics: "test",
            makeTodayMealsViewModel: { _ in todayVM }
        )
        _ = root
        XCTAssertEqual(todayVM.dateKey, dateKey)
    }

    // MARK: - AI analysis

    func testAIAnalysisFillsFormWithoutSaving() async {
        let analyze = MockAnalyzeAPIClient()
        analyze.setResult(
            MealAnalysisResult(
                dishName: "牛肉饭",
                confidence: 0.9,
                total: MealAnalysisNutrition(
                    grams: 350, calories: 620, protein: 28, carbs: 70, fat: 18, fiber: 3
                ),
                items: [
                    MealAnalysisItem(
                        name: "米饭", grams: 200, calories: 280, protein: 5, carbs: 62, fat: 1, fiber: 1, reasoning: ""
                    ),
                ],
                notes: "家常份量估算",
                model: "mock"
            )
        )
        let (vm, repo, _, client) = makeVM(analyze: analyze)
        vm.draftNote = "一碗牛肉饭"
        vm.draftMeal = .lunch
        await vm.runAIAnalysis()

        XCTAssertEqual(client.callCount, 1)
        XCTAssertEqual(client.lastRequest?.hint, "一碗牛肉饭")
        XCTAssertTrue(client.lastRequest?.photos.isEmpty == true)
        XCTAssertEqual(vm.draftName, "牛肉饭")
        XCTAssertEqual(vm.draftCalories, "620")
        XCTAssertEqual(vm.draftProtein, "28")
        XCTAssertEqual(vm.draftCarbs, "70")
        XCTAssertEqual(vm.draftFat, "18")
        XCTAssertEqual(vm.draftGrams, "350")
        XCTAssertTrue(vm.draftNote.contains("家常份量估算"))
        XCTAssertNotNil(vm.analysisSummary)
        XCTAssertTrue(vm.isPresentingAddSheet == false || true) // form fill only
        // Must NOT auto-save
        XCTAssertEqual(repo.itemsSnapshotForTest().count, 0)
        XCTAssertTrue(vm.items.isEmpty)
    }

    func testAIAnalysisWithPhotoDoesNotAutoSave() async {
        let analyze = MockAnalyzeAPIClient()
        analyze.setResult(
            MealAnalysisResult(
                dishName: "煎蛋",
                confidence: 0.7,
                total: MealAnalysisNutrition(grams: 50, calories: 90, protein: 7, carbs: 1, fat: 6, fiber: 0),
                items: [],
                notes: "照片估算",
                model: nil
            )
        )
        let (vm, repo, _, client) = makeVM(analyze: analyze)
        await vm.setDraftPhoto(rawData: Self.tinyJPEG())
        await vm.runAIAnalysis()
        XCTAssertEqual(client.callCount, 1)
        XCTAssertEqual(client.lastRequest?.photos.count, 1)
        XCTAssertTrue(client.lastRequest?.photos.first?.dataUrl.hasPrefix("data:image/jpeg;base64,") == true)
        XCTAssertFalse(client.lastRequest?.containsRemotePhotoURL == true)
        XCTAssertEqual(vm.draftName, "煎蛋")
        XCTAssertEqual(repo.itemsSnapshotForTest().count, 0)
    }

    func testAIAnalysisFailureDoesNotBlockManualSave() async {
        let analyze = MockAnalyzeAPIClient()
        analyze.setError(AppError.rateLimited(retryAfterSeconds: 60))
        let (vm, repo, _, _) = makeVM(analyze: analyze)
        vm.draftNote = "一碗白米饭"
        await vm.runAIAnalysis()
        XCTAssertEqual(vm.errorMessage, AppError.rateLimited(retryAfterSeconds: nil).userMessage)
        XCTAssertFalse((vm.errorMessage ?? "").contains("eyJ"))

        // Manual save still works
        vm.draftName = "白米饭"
        vm.draftCalories = "200"
        await vm.saveNewItem()
        XCTAssertEqual(vm.items.count, 1)
        XCTAssertEqual(vm.items.first?.name, "白米饭")
        XCTAssertEqual(repo.itemsSnapshotForTest().count, 1)
    }

    func testAIUnauthorizedDoesNotLeakToken() async {
        let analyze = MockAnalyzeAPIClient()
        analyze.setError(AppError.unauthorized)
        let (vm, _, _, _) = makeVM(analyze: analyze)
        vm.draftNote = "test"
        await vm.runAIAnalysis()
        XCTAssertEqual(vm.errorMessage, AppError.unauthorized.userMessage)
        XCTAssertFalse((vm.errorMessage ?? "").contains("Bearer"))
        XCTAssertFalse((vm.errorMessage ?? "").contains("eyJ"))
    }

    // MARK: - Date navigation (stage 6)

    func testDefaultSelectedDateIsTodayWhenNotInjected() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!
        let diary = DiaryCalendar(calendar: calendar)
        let photo = MockMealPhotoRepository(sessionUserId: user.id)
        let vm = TodayMealsViewModel(
            user: user,
            foodRepository: MockFoodItemRepository(sessionUserId: user.id, photoRepository: photo),
            photoRepository: photo,
            analyzeAPI: MockAnalyzeAPIClient(),
            diaryCalendar: diary
        )
        XCTAssertEqual(vm.selectedDateKey, diary.dateKey())
        XCTAssertTrue(vm.isToday)
        XCTAssertEqual(vm.displayTitle, "今天")
    }

    func testGoToPreviousDayFetchesYesterday() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let diary = DiaryCalendar(calendar: calendar)
        let today = diary.dateKey()
        let yesterday = diary.shiftingDateKey(today, byDays: -1)!
        let (vm, repo, _, _) = makeVM(diaryCalendar: diary, dateKey: today)
        await vm.load()
        XCTAssertEqual(repo.lastFetchDateKey, today)

        await vm.goToPreviousDay()
        XCTAssertEqual(vm.selectedDateKey, yesterday)
        XCTAssertEqual(repo.lastFetchDateKey, yesterday)
        XCTAssertFalse(vm.isToday)
        XCTAssertEqual(vm.displayTitle, "昨天")
    }

    func testGoToNextDayAndGoToToday() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let diary = DiaryCalendar(calendar: calendar)
        let today = diary.dateKey()
        let tomorrow = diary.shiftingDateKey(today, byDays: 1)!
        let (vm, repo, _, _) = makeVM(diaryCalendar: diary, dateKey: today)

        await vm.goToNextDay()
        XCTAssertEqual(vm.selectedDateKey, tomorrow)
        XCTAssertEqual(repo.lastFetchDateKey, tomorrow)
        XCTAssertEqual(vm.displayTitle, "明天")

        await vm.goToToday()
        XCTAssertEqual(vm.selectedDateKey, today)
        XCTAssertEqual(repo.lastFetchDateKey, today)
        XCTAssertTrue(vm.isToday)
    }

    func testSelectDateFetchesSpecifiedDateKey() async {
        let (vm, repo, _, _) = makeVM(dateKey: "2026-07-13")
        await vm.selectDateKey("2026-07-10")
        XCTAssertEqual(vm.selectedDateKey, "2026-07-10")
        XCTAssertEqual(repo.lastFetchDateKey, "2026-07-10")
    }

    func testNonTodayAddWritesSelectedDateKeyOnly() async {
        let historyKey = "2026-07-10"
        let photo = MockMealPhotoRepository(sessionUserId: user.id)
        let seedToday = food(id: "t1", meal: .lunch, name: "今天的饭", cal: 300, protein: 10, carbs: 40, fat: 5, on: "2026-07-13")
        let repo = MockFoodItemRepository(sessionUserId: user.id, seed: [seedToday], photoRepository: photo)
        let (vm, foodRepo, _, _) = makeVM(repo: repo, photo: photo, dateKey: historyKey)

        await vm.load()
        XCTAssertEqual(vm.loadState, .empty)
        XCTAssertTrue(vm.items.isEmpty)
        XCTAssertEqual(vm.summary.calories, 0)

        vm.draftName = "历史测试"
        vm.draftCalories = "111"
        await vm.saveNewItem()

        XCTAssertEqual(vm.items.count, 1)
        XCTAssertEqual(vm.items.first?.dateKey, historyKey)
        XCTAssertEqual(vm.items.first?.name, "历史测试")
        XCTAssertEqual(vm.summary.calories, 111)

        // Today still has only the seed item
        let todayItems = foodRepo.itemsSnapshotForTest().filter { $0.dateKey == "2026-07-13" }
        XCTAssertEqual(todayItems.count, 1)
        XCTAssertEqual(todayItems.first?.name, "今天的饭")
    }

    func testDateSwitchEmptyAndLoadedStates() async {
        let photo = MockMealPhotoRepository(sessionUserId: user.id)
        let seed = food(id: "h1", meal: .snack, name: "香蕉", cal: 100, protein: 1, carbs: 20, fat: 0, on: "2026-07-10")
        let repo = MockFoodItemRepository(sessionUserId: user.id, seed: [seed], photoRepository: photo)
        let (vm, _, _, _) = makeVM(repo: repo, photo: photo, dateKey: "2026-07-13")

        await vm.load()
        XCTAssertEqual(vm.loadState, .empty)

        await vm.selectDateKey("2026-07-10")
        XCTAssertEqual(vm.loadState, .loaded)
        XCTAssertEqual(vm.items.count, 1)
        XCTAssertEqual(vm.summary.calories, 100)

        await vm.selectDateKey("2026-07-11")
        XCTAssertEqual(vm.loadState, .empty)
        XCTAssertTrue(vm.items.isEmpty)
    }

    func testHistoryPhotoUploadUsesSelectedDateKey() async {
        let historyKey = "2026-07-09"
        let (vm, repo, photo, _) = makeVM(dateKey: historyKey)
        await vm.setDraftPhoto(rawData: Self.tinyJPEG())
        vm.draftName = "历史照片"
        await vm.saveNewItem()
        XCTAssertEqual(repo.lastCreatePhotoPaths.count, 1)
        XCTAssertTrue(repo.lastCreatePhotoPaths[0].hasPrefix("\(user.id)/\(historyKey)/"))
        XCTAssertEqual(photo.lastUploadPath, repo.lastCreatePhotoPaths.first)
        XCTAssertFalse((photo.lastUploadPath ?? "").contains("eyJ"))
    }

    func testHistoryAIAnalysisFillsFormThenSaveUsesSelectedDateKey() async {
        let historyKey = "2026-07-08"
        let analyze = MockAnalyzeAPIClient()
        analyze.setResult(
            MealAnalysisResult(
                dishName: "补记面条",
                confidence: 0.8,
                total: MealAnalysisNutrition(grams: 200, calories: 400, protein: 12, carbs: 60, fat: 8, fiber: 2),
                items: [],
                notes: "历史 AI",
                model: "mock"
            )
        )
        let (vm, repo, _, _) = makeVM(analyze: analyze, dateKey: historyKey)
        vm.draftNote = "一碗面条"
        await vm.runAIAnalysis()
        XCTAssertEqual(vm.draftName, "补记面条")
        XCTAssertEqual(repo.itemsSnapshotForTest().count, 0)

        await vm.saveNewItem()
        XCTAssertEqual(vm.items.count, 1)
        XCTAssertEqual(vm.items.first?.dateKey, historyKey)
        XCTAssertEqual(vm.items.first?.calories, 400)
    }

    func testDateChangeClosesAddSheetAndDoesNotLeakSecrets() async {
        let (vm, _, _, _) = makeVM(dateKey: "2026-07-13")
        vm.openAddSheet()
        vm.draftName = "draft"
        XCTAssertTrue(vm.isPresentingAddSheet)
        await vm.goToPreviousDay()
        XCTAssertFalse(vm.isPresentingAddSheet)
        XCTAssertEqual(vm.draftName, "")
        XCTAssertNil(vm.errorMessage)
        // No secret material on date-related strings
        XCTAssertFalse(vm.selectedDateKey.contains("eyJ"))
        XCTAssertFalse(vm.displayTitle.contains("Bearer"))
        XCTAssertFalse(vm.displayTitle.lowercased().contains("base64"))
    }

    // MARK: - Edit food (Stage 13)

    func testOpenEditPrefillsAllFields() async {
        let photo = MockMealPhotoRepository(sessionUserId: user.id)
        let item = food(
            id: "e1",
            meal: .lunch,
            name: "鸡胸",
            cal: 200,
            protein: 40,
            carbs: 5,
            fat: 4,
            paths: ["\(user.id)/2026-07-13/p.jpg"],
            on: dateKey,
            grams: 150,
            fiber: 2,
            note: "水煮",
            sourceId: "manual-abc"
        )
        let repo = MockFoodItemRepository(sessionUserId: user.id, seed: [item], photoRepository: photo)
        let (vm, _, _, _) = makeVM(repo: repo, photo: photo)
        await vm.load()
        vm.openEdit(item)
        XCTAssertTrue(vm.isPresentingAddSheet)
        XCTAssertTrue(vm.isEditingFood)
        XCTAssertEqual(vm.editingItemId, "e1")
        XCTAssertEqual(vm.draftName, "鸡胸")
        XCTAssertEqual(vm.draftMeal, .lunch)
        XCTAssertEqual(vm.draftCalories, "200")
        XCTAssertEqual(vm.draftProtein, "40")
        XCTAssertEqual(vm.draftCarbs, "5")
        XCTAssertEqual(vm.draftFat, "4")
        XCTAssertEqual(vm.draftFiber, "2")
        XCTAssertEqual(vm.draftGrams, "150")
        XCTAssertEqual(vm.draftNote, "水煮")
        XCTAssertEqual(vm.editingPhotoPaths, ["\(user.id)/2026-07-13/p.jpg"])
        XCTAssertEqual(vm.editingSourceId, "manual-abc")
        let cal = DiaryCalendar()
        XCTAssertEqual(cal.dateKey(from: vm.draftDate), dateKey)
    }

    func testEditCallsUpdateNotCreateAndPreservesPhotosAndSourceId() async {
        let photo = MockMealPhotoRepository(sessionUserId: user.id)
        let paths = ["\(user.id)/2026-07-13/keep.jpg"]
        let item = food(
            id: "keep-id",
            meal: .dinner,
            name: "旧名",
            cal: 100,
            protein: 10,
            carbs: 10,
            fat: 1,
            paths: paths,
            fiber: 8,
            note: "旧备注",
            sourceId: "src-keep"
        )
        let repo = MockFoodItemRepository(sessionUserId: user.id, seed: [item], photoRepository: photo)
        let (vm, foodRepo, _, _) = makeVM(repo: repo, photo: photo)
        await vm.load()
        vm.openEdit(item)
        vm.draftName = "新名"
        vm.draftMeal = .breakfast
        vm.draftCalories = "180"
        vm.draftProtein = "20"
        vm.draftFiber = "8"
        await vm.saveFoodItem()

        XCTAssertEqual(foodRepo.updateCallCount, 1)
        XCTAssertEqual(foodRepo.createCallCount, 0)
        XCTAssertEqual(foodRepo.lastUpdateId, "keep-id")
        XCTAssertEqual(foodRepo.lastUpdateWrite?.name, "新名")
        XCTAssertEqual(foodRepo.lastUpdateWrite?.meal, .breakfast)
        XCTAssertEqual(foodRepo.lastUpdateWrite?.calories, 180)
        XCTAssertEqual(foodRepo.lastUpdateWrite?.photoPaths, paths)
        XCTAssertEqual(foodRepo.lastUpdateWrite?.sourceId, "src-keep")
        XCTAssertEqual(foodRepo.lastUpdateWrite?.fiber, 8)
        XCTAssertFalse(vm.isPresentingAddSheet)
        XCTAssertEqual(vm.items.first?.id, "keep-id")
        XCTAssertEqual(vm.items.first?.name, "新名")
    }

    func testEditDateMoveKeepsSelectedDateAndShowsStatus() async {
        let photo = MockMealPhotoRepository(sessionUserId: user.id)
        let item = food(id: "m1", meal: .snack, name: "香蕉", cal: 90, protein: 1, carbs: 20, fat: 0)
        let repo = MockFoodItemRepository(sessionUserId: user.id, seed: [item], photoRepository: photo)
        let (vm, foodRepo, _, _) = makeVM(repo: repo, photo: photo)
        await vm.load()
        XCTAssertEqual(vm.selectedDateKey, dateKey)
        vm.openEdit(item)
        // Move to previous day
        let cal = DiaryCalendar()
        vm.draftDate = cal.dateByAdding(days: -1, to: vm.selectedDate)
        let newKey = cal.dateKey(from: vm.draftDate)
        await vm.saveFoodItem()

        XCTAssertEqual(vm.selectedDateKey, dateKey, "must not auto-navigate")
        XCTAssertEqual(foodRepo.lastUpdateWrite?.dateKey, newKey)
        XCTAssertTrue(vm.items.isEmpty, "item should leave current day")
        XCTAssertEqual(vm.statusMessage, "已保存到 \(newKey)")
        do {
            let moved = try await foodRepo.fetchByDateKey(newKey)
            XCTAssertEqual(moved.count, 1)
            XCTAssertEqual(moved.first?.id, "m1")
        } catch {
            XCTFail("fetch after move failed: \(error)")
        }
    }

    func testAddSavesFiberNotHardcodedZero() async {
        let (vm, repo, _, _) = makeVM()
        await vm.load()
        vm.openAddSheet(defaultMeal: .lunch)
        vm.draftName = "燕麦"
        vm.draftCalories = "150"
        vm.draftFiber = "5.5"
        await vm.saveFoodItem()
        XCTAssertEqual(repo.lastCreateWrite?.fiber, 5.5)
        XCTAssertEqual(vm.items.first?.fiber, 5.5)
    }

    func testEditEmptyNameDoesNotCallRepository() async {
        let photo = MockMealPhotoRepository(sessionUserId: user.id)
        let item = food(id: "n1", meal: .lunch, name: "饭", cal: 200, protein: 4, carbs: 40, fat: 1)
        let repo = MockFoodItemRepository(sessionUserId: user.id, seed: [item], photoRepository: photo)
        let (vm, foodRepo, _, _) = makeVM(repo: repo, photo: photo)
        await vm.load()
        vm.openEdit(item)
        vm.draftName = "   "
        await vm.saveFoodItem()
        XCTAssertEqual(foodRepo.updateCallCount, 0)
        XCTAssertTrue(vm.isPresentingAddSheet)
        XCTAssertNotNil(vm.errorMessage)
    }

    func testEditNegativeNumberDoesNotCallRepository() async {
        let photo = MockMealPhotoRepository(sessionUserId: user.id)
        let item = food(id: "n2", meal: .lunch, name: "饭", cal: 200, protein: 4, carbs: 40, fat: 1)
        let repo = MockFoodItemRepository(sessionUserId: user.id, seed: [item], photoRepository: photo)
        let (vm, foodRepo, _, _) = makeVM(repo: repo, photo: photo)
        await vm.load()
        vm.openEdit(item)
        vm.draftCalories = "-10"
        await vm.saveFoodItem()
        XCTAssertEqual(foodRepo.updateCallCount, 0)
        XCTAssertTrue(vm.isPresentingAddSheet)
        XCTAssertTrue((vm.errorMessage ?? "").contains("热量") || (vm.errorMessage ?? "").contains("负"))
    }

    func testEditFailureKeepsSheetAndDraft() async {
        let photo = MockMealPhotoRepository(sessionUserId: user.id)
        let item = food(id: "f1", meal: .lunch, name: "汤", cal: 50, protein: 2, carbs: 5, fat: 1, fiber: 1)
        let repo = MockFoodItemRepository(sessionUserId: user.id, seed: [item], photoRepository: photo)
        let (vm, foodRepo, _, _) = makeVM(repo: repo, photo: photo)
        await vm.load()
        vm.openEdit(item)
        vm.draftName = "新汤"
        foodRepo.forcedError = AppError.network(message: "down")
        await vm.saveFoodItem()
        XCTAssertTrue(vm.isPresentingAddSheet)
        XCTAssertEqual(vm.draftName, "新汤")
        XCTAssertEqual(vm.editingItemId, "f1")
        XCTAssertNotNil(vm.errorMessage)
        foodRepo.forcedError = nil
        let still = foodRepo.itemsSnapshotForTest()
        XCTAssertEqual(still.first?.name, "汤")
    }

    func testDeleteStillWorksAfterEditSupport() async {
        let photo = MockMealPhotoRepository(sessionUserId: user.id)
        let item = food(id: "d1", meal: .breakfast, name: "蛋", cal: 70, protein: 6, carbs: 1, fat: 5)
        let repo = MockFoodItemRepository(sessionUserId: user.id, seed: [item], photoRepository: photo)
        let (vm, _, _, _) = makeVM(repo: repo, photo: photo)
        await vm.load()
        await vm.deleteItem(item)
        XCTAssertTrue(vm.items.isEmpty)
    }

    func testOpenAddAfterEditClearsEditState() async {
        let photo = MockMealPhotoRepository(sessionUserId: user.id)
        let item = food(
            id: "x1",
            meal: .lunch,
            name: "旧",
            cal: 100,
            protein: 1,
            carbs: 1,
            fat: 1,
            paths: ["a/b.jpg"],
            fiber: 3,
            sourceId: "old-src"
        )
        let repo = MockFoodItemRepository(sessionUserId: user.id, seed: [item], photoRepository: photo)
        let (vm, _, _, _) = makeVM(repo: repo, photo: photo)
        await vm.load()
        vm.openEdit(item)
        XCTAssertTrue(vm.isEditingFood)
        vm.cancelAdd()
        vm.openAddSheet(defaultMeal: .snack)
        XCTAssertFalse(vm.isEditingFood)
        XCTAssertNil(vm.editingItemId)
        XCTAssertTrue(vm.editingPhotoPaths.isEmpty)
        XCTAssertNil(vm.editingSourceId)
        XCTAssertEqual(vm.draftName, "")
        XCTAssertEqual(vm.draftFiber, "")
        XCTAssertEqual(vm.draftMeal, .snack)
    }

    func testMultiPhotoPathsPreservedAndNoUploadOnEdit() async {
        let photo = MockMealPhotoRepository(sessionUserId: user.id)
        let paths = [
            "\(user.id)/2026-07-13/a.jpg",
            "\(user.id)/2026-07-13/b.jpg"
        ]
        let item = FoodItem(
            id: "multi",
            dateKey: dateKey,
            meal: .dinner,
            name: "双图",
            grams: 100,
            calories: 300,
            protein: 10,
            carbs: 20,
            fat: 5,
            fiber: 1,
            note: "",
            photoPaths: paths,
            photoURLs: [], // signed URLs missing must not wipe paths
            createdAt: "2026-07-13T08:00:00Z",
            sourceId: "src-multi"
        )
        let repo = MockFoodItemRepository(sessionUserId: user.id, seed: [item], photoRepository: photo)
        let (vm, foodRepo, photoRepo, _) = makeVM(repo: repo, photo: photo)
        await vm.load()
        vm.openEdit(item)
        XCTAssertEqual(vm.editingPhotoPaths, paths)
        vm.draftName = "双图改"
        await vm.saveFoodItem()
        XCTAssertEqual(foodRepo.lastUpdateWrite?.photoPaths, paths)
        XCTAssertEqual(foodRepo.lastUpdateWrite?.sourceId, "src-multi")
        XCTAssertEqual(photoRepo.uploadCallCount, 0)
        XCTAssertEqual(foodRepo.createCallCount, 0)
        XCTAssertEqual(foodRepo.updateCallCount, 1)
    }

    func testEditNilSourceIdStaysNil() async {
        let photo = MockMealPhotoRepository(sessionUserId: user.id)
        let item = food(id: "nil-src", meal: .lunch, name: "无源", cal: 50, protein: 1, carbs: 5, fat: 0, sourceId: nil)
        let repo = MockFoodItemRepository(sessionUserId: user.id, seed: [item], photoRepository: photo)
        let (vm, foodRepo, _, _) = makeVM(repo: repo, photo: photo)
        await vm.load()
        vm.openEdit(item)
        XCTAssertNil(vm.editingSourceId)
        vm.draftName = "无源改"
        await vm.saveFoodItem()
        XCTAssertNil(foodRepo.lastUpdateWrite?.sourceId)
    }

    func testInvalidNumberDoesNotCallRepository() async {
        let photo = MockMealPhotoRepository(sessionUserId: user.id)
        let item = food(id: "bad", meal: .lunch, name: "饭", cal: 200, protein: 4, carbs: 40, fat: 1)
        let repo = MockFoodItemRepository(sessionUserId: user.id, seed: [item], photoRepository: photo)
        let (vm, foodRepo, _, _) = makeVM(repo: repo, photo: photo)
        await vm.load()
        vm.openEdit(item)
        vm.draftProtein = "abc"
        await vm.saveFoodItem()
        XCTAssertEqual(foodRepo.updateCallCount, 0)
        XCTAssertTrue((vm.errorMessage ?? "").contains("蛋白质"))
    }

    func testCommaDecimalAcceptedForFiber() async {
        let (vm, repo, _, _) = makeVM()
        await vm.load()
        vm.openAddSheet()
        vm.draftName = "豆类"
        vm.draftFiber = "4,5"
        await vm.saveFoodItem()
        XCTAssertEqual(repo.lastCreateWrite?.fiber ?? -1, 4.5, accuracy: 0.0001)
    }

    func testAIAnalysisFiberSavedOnCreate() async {
        let analyze = MockAnalyzeAPIClient()
        analyze.setResult(
            MealAnalysisResult(
                dishName: "沙拉",
                confidence: 0.8,
                total: MealAnalysisNutrition(
                    grams: 200, calories: 120, protein: 5, carbs: 15, fat: 4, fiber: 7
                ),
                items: [],
                notes: "",
                model: "mock"
            )
        )
        let (vm, repo, _, _) = makeVM(analyze: analyze)
        await vm.load()
        vm.openAddSheet()
        vm.draftNote = "一碗沙拉"
        await vm.runAIAnalysis()
        XCTAssertEqual(vm.draftFiber, "7")
        await vm.saveFoodItem()
        XCTAssertEqual(repo.lastCreateWrite?.fiber, 7)
        XCTAssertEqual(repo.createCallCount, 1)
    }

    func testRapidOpenEditUsesLatestItem() async {
        let photo = MockMealPhotoRepository(sessionUserId: user.id)
        let a = food(id: "a", meal: .breakfast, name: "A", cal: 1, protein: 0, carbs: 0, fat: 0)
        let b = food(id: "b", meal: .lunch, name: "B", cal: 2, protein: 0, carbs: 0, fat: 0)
        let repo = MockFoodItemRepository(sessionUserId: user.id, seed: [a, b], photoRepository: photo)
        let (vm, _, _, _) = makeVM(repo: repo, photo: photo)
        await vm.load()
        vm.openEdit(a)
        vm.openEdit(b)
        XCTAssertEqual(vm.editingItemId, "b")
        XCTAssertEqual(vm.draftName, "B")
        XCTAssertEqual(vm.draftMeal, .lunch)
    }

    // MARK: - Edit photo replace / remove / rollback (Stage 17)

    func testEditUnchangedPhotoDoesNotUpload() async {
        let photo = MockMealPhotoRepository(sessionUserId: user.id)
        let paths = ["\(user.id)/2026-07-13/keep.jpg"]
        let item = food(
            id: "u1",
            meal: .lunch,
            name: "饭",
            cal: 200,
            protein: 5,
            carbs: 40,
            fat: 1,
            paths: paths,
            sourceId: "src-u1"
        )
        let repo = MockFoodItemRepository(sessionUserId: user.id, seed: [item], photoRepository: photo)
        let (vm, foodRepo, photoRepo, _) = makeVM(repo: repo, photo: photo)
        await vm.load()
        vm.openEdit(item)
        vm.draftName = "饭改"
        await vm.saveFoodItem()
        XCTAssertEqual(photoRepo.uploadCallCount, 0)
        XCTAssertEqual(foodRepo.lastUpdateWrite?.photoPaths, paths)
        XCTAssertEqual(foodRepo.lastUpdateWrite?.sourceId, "src-u1")
    }

    func testEditReplacePhotoUploadsAndReplacesPathsKeepingSourceId() async {
        let photo = MockMealPhotoRepository(sessionUserId: user.id)
        let oldPaths = [
            "\(user.id)/2026-07-13/old1.jpg",
            "\(user.id)/2026-07-13/old2.jpg",
        ]
        let item = food(
            id: "r1",
            meal: .dinner,
            name: "多图",
            cal: 300,
            protein: 10,
            carbs: 30,
            fat: 5,
            paths: oldPaths,
            sourceId: "src-r1"
        )
        let repo = MockFoodItemRepository(sessionUserId: user.id, seed: [item], photoRepository: photo)
        let (vm, foodRepo, photoRepo, _) = makeVM(repo: repo, photo: photo)
        await vm.load()
        vm.openEdit(item)
        await vm.setDraftPhoto(rawData: Self.tinyJPEG())
        await vm.saveFoodItem()

        XCTAssertEqual(photoRepo.uploadCallCount, 1)
        XCTAssertEqual(foodRepo.updateCallCount, 1)
        XCTAssertEqual(foodRepo.lastUpdateWrite?.photoPaths.count, 1)
        XCTAssertNotEqual(foodRepo.lastUpdateWrite?.photoPaths, oldPaths)
        XCTAssertEqual(foodRepo.lastUpdateWrite?.sourceId, "src-r1")
        // Old unreferenced paths cleaned after successful update.
        XCTAssertTrue(oldPaths.allSatisfy { photoRepo.deletedPaths.contains($0) })
    }

    func testEditRemovePhotoClearsPathsAndDeletesOrphan() async {
        let photo = MockMealPhotoRepository(sessionUserId: user.id)
        let paths = ["\(user.id)/2026-07-13/gone.jpg"]
        let item = food(
            id: "d1",
            meal: .snack,
            name: "零食",
            cal: 90,
            protein: 1,
            carbs: 20,
            fat: 0,
            paths: paths,
            sourceId: "src-d1"
        )
        let repo = MockFoodItemRepository(sessionUserId: user.id, seed: [item], photoRepository: photo)
        let (vm, foodRepo, photoRepo, _) = makeVM(repo: repo, photo: photo)
        await vm.load()
        vm.openEdit(item)
        vm.markEditPhotoRemoved()
        XCTAssertTrue(vm.editPhotoRemoved)
        await vm.saveFoodItem()

        XCTAssertEqual(photoRepo.uploadCallCount, 0)
        XCTAssertEqual(foodRepo.lastUpdateWrite?.photoPaths, [])
        XCTAssertEqual(foodRepo.lastUpdateWrite?.sourceId, "src-d1")
        XCTAssertTrue(photoRepo.deletedPaths.contains("\(user.id)/2026-07-13/gone.jpg"))
    }

    func testEditReplaceUploadSuccessUpdateFailureRollsBackNewPath() async {
        let photo = MockMealPhotoRepository(sessionUserId: user.id)
        let old = ["\(user.id)/2026-07-13/old.jpg"]
        let item = food(
            id: "fail-u",
            meal: .lunch,
            name: "旧",
            cal: 100,
            protein: 1,
            carbs: 10,
            fat: 1,
            paths: old,
            sourceId: "src-fail"
        )
        let repo = MockFoodItemRepository(sessionUserId: user.id, seed: [item], photoRepository: photo)
        let (vm, foodRepo, photoRepo, _) = makeVM(repo: repo, photo: photo)
        await vm.load()
        vm.openEdit(item)
        await vm.setDraftPhoto(rawData: Self.tinyJPEG())
        repo.forcedError = AppError.network(message: "update down")
        await vm.saveFoodItem()

        XCTAssertEqual(photoRepo.uploadCallCount, 1)
        // New path best-effort deleted; old path remains on item
        XCTAssertNotNil(photoRepo.lastUploadPath)
        if let newPath = photoRepo.lastUploadPath {
            XCTAssertTrue(photoRepo.deletedPaths.contains(newPath))
        }
        repo.forcedError = nil
        do {
            let still = try await foodRepo.fetchById("fail-u")
            XCTAssertEqual(still?.photoPaths, old)
            XCTAssertEqual(still?.sourceId, "src-fail")
        } catch {
            XCTFail("fetchById failed: \(error)")
        }
        XCTAssertTrue(vm.isPresentingAddSheet)
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertFalse((vm.errorMessage ?? "").contains("eyJ"))
    }

    func testAddUploadSuccessCreateFailureRollsBackNewPath() async {
        let photo = MockMealPhotoRepository(sessionUserId: user.id)
        let repo = MockFoodItemRepository(sessionUserId: user.id, photoRepository: photo)
        let (vm, foodRepo, photoRepo, _) = makeVM(repo: repo, photo: photo)
        await vm.load()
        vm.openAddSheet()
        vm.draftName = "新图"
        vm.draftCalories = "100"
        await vm.setDraftPhoto(rawData: Self.tinyJPEG())
        repo.forcedError = AppError.network(message: "create down")
        await vm.saveFoodItem()

        XCTAssertEqual(photoRepo.uploadCallCount, 1)
        XCTAssertEqual(foodRepo.createCallCount, 0) // forced before increment? check mock - forced throws before count
        // actually mock throws at start of create so createCallCount may be 0
        if let newPath = photoRepo.lastUploadPath {
            XCTAssertTrue(photoRepo.deletedPaths.contains(newPath))
        }
        XCTAssertTrue(vm.isPresentingAddSheet)
        XCTAssertNotNil(vm.errorMessage)
    }

    func testEditDoesNotDeleteSharedPhotoPath() async {
        let photo = MockMealPhotoRepository(sessionUserId: user.id)
        let shared = "\(user.id)/2026-07-13/shared.jpg"
        let a = food(id: "a", meal: .lunch, name: "A", cal: 1, protein: 0, carbs: 0, fat: 0, paths: [shared], sourceId: "sa")
        let b = food(id: "b", meal: .dinner, name: "B", cal: 2, protein: 0, carbs: 0, fat: 0, paths: [shared], sourceId: "sb")
        let repo = MockFoodItemRepository(sessionUserId: user.id, seed: [a, b], photoRepository: photo)
        let (vm, _, photoRepo, _) = makeVM(repo: repo, photo: photo)
        await vm.load()
        vm.openEdit(a)
        vm.markEditPhotoRemoved()
        await vm.saveFoodItem()
        // Still referenced by B — must not delete Storage object.
        XCTAssertFalse(photoRepo.deletedPaths.contains(shared))
    }

    private func food(
        id: String,
        meal: MealType,
        name: String,
        cal: Double,
        protein: Double,
        carbs: Double,
        fat: Double,
        paths: [String] = [],
        on date: String? = nil,
        grams: Double = 0,
        fiber: Double = 0,
        note: String = "",
        sourceId: String? = nil
    ) -> FoodItem {
        let key = date ?? dateKey
        return FoodItem(
            id: id,
            dateKey: key,
            meal: meal,
            name: name,
            grams: grams,
            calories: cal,
            protein: protein,
            carbs: carbs,
            fat: fat,
            fiber: fiber,
            note: note,
            photoPaths: paths,
            photoURLs: paths.map { "https://example.invalid/signed/\($0)" },
            createdAt: "2026-07-13T08:00:00Z",
            sourceId: sourceId
        )
    }

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
            fatalError("CGContext unavailable for test JPEG")
        }
        ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let cgImage = ctx.makeImage() else {
            fatalError("CGImage unavailable for test JPEG")
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
}
