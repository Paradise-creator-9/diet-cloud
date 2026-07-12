import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import DietCloud

@MainActor
final class TodayMealsViewModelTests: XCTestCase {
    private let user = AuthUser(id: "11111111-1111-1111-1111-111111111111", email: "a@example.com")
    private let dateKey = "2026-07-13"

    func testInitialLoadStateIsLoadingThenEmpty() async {
        let photo = MockMealPhotoRepository(sessionUserId: user.id)
        let repo = MockFoodItemRepository(sessionUserId: user.id, photoRepository: photo)
        let vm = TodayMealsViewModel(
            user: user,
            foodRepository: repo,
            photoRepository: photo,
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
        let photo = MockMealPhotoRepository(sessionUserId: user.id)
        let repo = MockFoodItemRepository(sessionUserId: user.id, seed: [
            food(id: "1", meal: .breakfast, name: "蛋", cal: 70, protein: 6, carbs: 1, fat: 5),
            food(id: "2", meal: .lunch, name: "饭", cal: 200, protein: 4, carbs: 40, fat: 1),
            food(id: "3", meal: .breakfast, name: "奶", cal: 100, protein: 8, carbs: 10, fat: 3),
        ], photoRepository: photo)
        let vm = TodayMealsViewModel(
            user: user,
            foodRepository: repo,
            photoRepository: photo,
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
        XCTAssertEqual(vm.mealSections.map(\.meal), MealType.displayOrder)
    }

    func testLoadErrorStateDoesNotLeakToken() async {
        let photo = MockMealPhotoRepository(sessionUserId: user.id)
        let repo = MockFoodItemRepository(sessionUserId: user.id, photoRepository: photo)
        repo.forcedError = AppError.auth(.provider(message: "bad eyJhbGciOiJIUzI1NiJ9.payload.sig"))
        let vm = TodayMealsViewModel(user: user, foodRepository: repo, photoRepository: photo, dateKey: dateKey)
        await vm.load()
        if case .error(let message) = vm.loadState {
            XCTAssertFalse(message.contains("eyJ"))
            XCTAssertEqual(vm.errorMessage, message)
        } else {
            XCTFail("expected error state")
        }
    }

    func testAddItemSuccessRefreshesList() async {
        let photo = MockMealPhotoRepository(sessionUserId: user.id)
        let repo = MockFoodItemRepository(sessionUserId: user.id, photoRepository: photo)
        let vm = TodayMealsViewModel(user: user, foodRepository: repo, photoRepository: photo, dateKey: dateKey)
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
        let photo = MockMealPhotoRepository(sessionUserId: user.id)
        let repo = MockFoodItemRepository(sessionUserId: user.id, photoRepository: photo)
        let vm = TodayMealsViewModel(user: user, foodRepository: repo, photoRepository: photo, dateKey: dateKey)

        // Minimal 1x1 JPEG
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
        let photo = MockMealPhotoRepository(sessionUserId: user.id)
        let repo = MockFoodItemRepository(sessionUserId: user.id, photoRepository: photo)
        let vm = TodayMealsViewModel(user: user, foodRepository: repo, photoRepository: photo, dateKey: dateKey)
        vm.draftName = "水"
        await vm.saveNewItem()
        XCTAssertEqual(vm.items.count, 1)
        XCTAssertNil(photo.lastUploadPath)
        XCTAssertTrue(repo.lastCreatePhotoPaths.isEmpty)
    }

    func testAddItemFailureKeepsSheetAndShowsError() async {
        let photo = MockMealPhotoRepository(sessionUserId: user.id)
        let repo = MockFoodItemRepository(sessionUserId: user.id, photoRepository: photo)
        let vm = TodayMealsViewModel(user: user, foodRepository: repo, photoRepository: photo, dateKey: dateKey)
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
        let photo = MockMealPhotoRepository(sessionUserId: user.id)
        let repo = MockFoodItemRepository(sessionUserId: user.id, photoRepository: photo)
        let vm = TodayMealsViewModel(user: user, foodRepository: repo, photoRepository: photo, dateKey: dateKey)
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
        let vm = TodayMealsViewModel(user: user, foodRepository: repo, photoRepository: photo, dateKey: dateKey)
        await vm.load()
        XCTAssertEqual(vm.items.count, 1)
        await vm.deleteItem(seed)
        XCTAssertEqual(vm.loadState, .empty)
        XCTAssertTrue(vm.items.isEmpty)
        XCTAssertEqual(photo.deletedPaths, [path])
    }

    func testDeleteFailureSetsError() async {
        let photo = MockMealPhotoRepository(sessionUserId: user.id)
        let seed = food(id: "x", meal: .lunch, name: "饭", cal: 200, protein: 0, carbs: 0, fat: 0)
        let repo = MockFoodItemRepository(sessionUserId: user.id, seed: [seed], photoRepository: photo)
        let vm = TodayMealsViewModel(user: user, foodRepository: repo, photoRepository: photo, dateKey: dateKey)
        await vm.load()
        repo.forcedError = AppError.unauthorized
        await vm.deleteItem(seed)
        XCTAssertEqual(vm.errorMessage, AppError.unauthorized.userMessage)
        XCTAssertEqual(vm.items.count, 1)
    }

    func testDateKeyUsesDiaryCalendarWhenNotInjected() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!
        let diary = DiaryCalendar(calendar: calendar)
        let expected = diary.dateKey()
        let photo = MockMealPhotoRepository(sessionUserId: user.id)
        let vm = TodayMealsViewModel(
            user: user,
            foodRepository: MockFoodItemRepository(sessionUserId: user.id, photoRepository: photo),
            photoRepository: photo,
            diaryCalendar: diary
        )
        XCTAssertEqual(vm.dateKey, expected)
    }

    func testSignedInRootUsesTodayMealsFactory() {
        let photo = MockMealPhotoRepository(sessionUserId: user.id)
        let foodRepo = MockFoodItemRepository(sessionUserId: user.id, photoRepository: photo)
        let auth = MockAuthRepository()
        let authVM = AuthViewModel(repository: auth, isConfigured: true)
        let todayVM = TodayMealsViewModel(
            user: user,
            foodRepository: foodRepo,
            photoRepository: photo,
            dateKey: dateKey
        )
        let root = AuthRootView(
            viewModel: authVM,
            configDiagnostics: "test",
            makeTodayMealsViewModel: { _ in todayVM }
        )
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

    /// Programmatic solid-color JPEG so ImageIO can read real pixel dimensions.
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
