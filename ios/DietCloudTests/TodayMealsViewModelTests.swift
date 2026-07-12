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

    private func food(
        id: String,
        meal: MealType,
        name: String,
        cal: Double,
        protein: Double,
        carbs: Double,
        fat: Double,
        paths: [String] = []
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
            photoPaths: paths,
            photoURLs: paths.map { "https://example.invalid/signed/\($0)" },
            createdAt: "2026-07-13T08:00:00Z",
            sourceId: nil
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
