import XCTest
@testable import DietCloud

@MainActor
final class PhotoLibraryBuilderTests: XCTestCase {
    private let userId = "11111111-1111-1111-1111-111111111111"

    func testFlattenSkipsFoodsWithoutPhotos() {
        let withPhoto = food(id: "a", paths: ["\(userId)/2026-07-13/a.jpg"], on: "2026-07-13")
        let noPhoto = food(id: "b", paths: [], on: "2026-07-13")
        let items = PhotoLibraryBuilder.flatten(foods: [withPhoto, noPhoto])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].foodId, "a")
        XCTAssertEqual(items[0].id, "a|\(userId)/2026-07-13/a.jpg")
    }

    func testSingleFoodMultiplePhotos() {
        let food = food(
            id: "m1",
            paths: [
                "\(userId)/2026-07-10/p1.jpg",
                "\(userId)/2026-07-10/p2.jpg",
            ],
            on: "2026-07-10",
            name: "双图",
            cal: 400
        )
        let items = PhotoLibraryBuilder.flatten(foods: [food])
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.map(\.foodId), ["m1", "m1"])
        XCTAssertEqual(items.map(\.name), ["双图", "双图"])
        XCTAssertEqual(Set(items.map(\.path)).count, 2)
        XCTAssertEqual(Set(items.map(\.id)).count, 2)
    }

    func testDuplicatePathsOnSameFoodCollapseToOneId() {
        let path = "\(userId)/2026-07-10/dup.jpg"
        let food = food(id: "dup", paths: [path, path, "  \(path)  "], on: "2026-07-10")
        let items = PhotoLibraryBuilder.flatten(foods: [food])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].id, "dup|\(path)")
        XCTAssertEqual(items[0].path, path)
    }

    func testAllCapKeepsNewestAfterSort() {
        // 3 items: newest day should survive if limit=2
        let a = food(id: "a", paths: ["u/2026-07-01/a.jpg"], on: "2026-07-01", createdAt: "2026-07-01T10:00:00Z")
        let b = food(id: "b", paths: ["u/2026-07-12/b.jpg"], on: "2026-07-12", createdAt: "2026-07-12T10:00:00Z")
        let c = food(id: "c", paths: ["u/2026-07-13/c.jpg"], on: "2026-07-13", createdAt: "2026-07-13T10:00:00Z")
        let sorted = PhotoLibraryBuilder.sorted(PhotoLibraryBuilder.flatten(foods: [a, b, c]))
        let (capped, wasCapped) = PhotoLibraryBuilder.capped(sorted, limit: 2)
        XCTAssertTrue(wasCapped)
        XCTAssertEqual(capped.map(\.foodId), ["c", "b"])
    }

    func testSortDateKeyDescThenCreatedAtDesc() {
        let older = food(
            id: "1",
            paths: ["u/2026-07-01/a.jpg"],
            on: "2026-07-01",
            createdAt: "2026-07-01T10:00:00Z"
        )
        let newerDay = food(
            id: "2",
            paths: ["u/2026-07-13/b.jpg"],
            on: "2026-07-13",
            createdAt: "2026-07-13T08:00:00Z"
        )
        let sameDayEarlier = food(
            id: "3",
            paths: ["u/2026-07-13/c.jpg"],
            on: "2026-07-13",
            createdAt: "2026-07-13T12:00:00Z"
        )
        let sorted = PhotoLibraryBuilder.sorted(
            PhotoLibraryBuilder.flatten(foods: [older, newerDay, sameDayEarlier])
        )
        XCTAssertEqual(sorted.map(\.foodId), ["3", "2", "1"])
    }

    func testCap100() {
        var foods: [FoodItem] = []
        for i in 0..<110 {
            let day = String(format: "2026-01-%02d", (i % 28) + 1)
            foods.append(food(
                id: "id-\(i)",
                paths: ["u/\(day)/p\(i).jpg"],
                on: day,
                createdAt: String(format: "2026-01-%02dT%02d:00:00Z", (i % 28) + 1, i % 24)
            ))
        }
        let sorted = PhotoLibraryBuilder.sorted(PhotoLibraryBuilder.flatten(foods: foods))
        let (capped, wasCapped) = PhotoLibraryBuilder.capped(sorted, limit: 100)
        XCTAssertEqual(capped.count, 100)
        XCTAssertTrue(wasCapped)
        XCTAssertEqual(sorted.count, 110)
    }

    func testBounds7And30IncludeToday() {
        let cal = DiaryCalendar.tokyo()
        let end = "2026-07-13"
        let b7 = PhotoLibraryBuilder.bounds(for: .days7, endingOn: end, calendar: cal)
        XCTAssertEqual(b7?.end, end)
        XCTAssertEqual(b7?.start, "2026-07-07")

        let b30 = PhotoLibraryBuilder.bounds(for: .days30, endingOn: end, calendar: cal)
        XCTAssertEqual(b30?.end, end)
        XCTAssertEqual(b30?.start, "2026-06-14")

        XCTAssertNil(PhotoLibraryBuilder.bounds(for: .all, endingOn: end, calendar: cal))
    }

    func testApplySignedURLsPartialAndAbsolute() {
        let items = [
            PhotoLibraryItem.from(
                food: food(id: "1", paths: ["u/d/a.jpg"], on: "2026-07-13"),
                path: "u/d/a.jpg"
            ),
            PhotoLibraryItem.from(
                food: food(id: "2", paths: ["u/d/b.jpg"], on: "2026-07-13"),
                path: "u/d/b.jpg"
            ),
            PhotoLibraryItem.from(
                food: food(id: "3", paths: ["https://cdn.example/x.jpg"], on: "2026-07-13"),
                path: "https://cdn.example/x.jpg"
            ),
        ]
        let refs = [
            MealPhotoRef(path: "u/d/a.jpg", signedURL: "https://signed/a"),
            MealPhotoRef(path: "u/d/b.jpg", signedURL: nil),
            MealPhotoRef(path: "https://cdn.example/x.jpg", signedURL: nil),
        ]
        let applied = PhotoLibraryBuilder.applySignedURLs(items: items, refs: refs)
        XCTAssertEqual(applied[0].signedURL, "https://signed/a")
        XCTAssertNil(applied[1].signedURL)
        XCTAssertEqual(applied[2].signedURL, "https://cdn.example/x.jpg")
    }

    func testDetailMappingFields() {
        let food = food(
            id: "d1",
            paths: ["u/2026-07-13/z.jpg"],
            on: "2026-07-13",
            name: "咖喱",
            meal: .dinner,
            cal: 520,
            protein: 18,
            carbs: 70,
            fat: 16,
            fiber: 5,
            note: "外食",
            grams: 350
        )
        let item = PhotoLibraryItem.from(food: food, path: food.photoPaths[0])
        XCTAssertEqual(item.name, "咖喱")
        XCTAssertEqual(item.meal, .dinner)
        XCTAssertEqual(item.dateKey, "2026-07-13")
        XCTAssertEqual(item.calories, 520)
        XCTAssertEqual(item.protein, 18)
        XCTAssertEqual(item.carbs, 70)
        XCTAssertEqual(item.fat, 16)
        XCTAssertEqual(item.fiber, 5)
        XCTAssertEqual(item.note, "外食")
        XCTAssertEqual(item.grams, 350)
    }

    private func food(
        id: String,
        paths: [String],
        on dateKey: String,
        name: String = "食物",
        meal: MealType = .lunch,
        cal: Double = 100,
        protein: Double = 1,
        carbs: Double = 2,
        fat: Double = 3,
        fiber: Double = 0,
        note: String = "",
        grams: Double = 0,
        createdAt: String = "2026-07-13T08:00:00Z"
    ) -> FoodItem {
        FoodItem(
            id: id,
            dateKey: dateKey,
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
            photoURLs: [],
            createdAt: createdAt,
            sourceId: nil
        )
    }
}

@MainActor
final class PhotoLibraryViewModelTests: XCTestCase {
    private let userId = "11111111-1111-1111-1111-111111111111"
    private let today = "2026-07-13"

    private func makeNow() -> Date {
        DiaryCalendar.tokyo().date(fromDateKey: today)!
    }

    private func makeVM(
        seed: [FoodItem] = [],
        photo: MockMealPhotoRepository? = nil
    ) -> (PhotoLibraryViewModel, MockFoodItemRepository, MockMealPhotoRepository) {
        let photoRepo = photo ?? MockMealPhotoRepository(sessionUserId: userId)
        let foodRepo = MockFoodItemRepository(sessionUserId: userId, seed: seed, photoRepository: photoRepo)
        let vm = PhotoLibraryViewModel(
            foodRepository: foodRepo,
            photoRepository: photoRepo,
            diaryCalendar: DiaryCalendar.tokyo(),
            nowProvider: { self.makeNow() }
        )
        return (vm, foodRepo, photoRepo)
    }

    private func food(
        id: String,
        paths: [String],
        on dateKey: String,
        name: String = "食物",
        meal: MealType = .lunch,
        cal: Double = 100,
        protein: Double = 10,
        carbs: Double = 20,
        fat: Double = 5,
        fiber: Double = 2,
        note: String = "",
        createdAt: String = "2026-07-13T08:00:00Z"
    ) -> FoodItem {
        FoodItem(
            id: id,
            dateKey: dateKey,
            meal: meal,
            name: name,
            grams: 100,
            calories: cal,
            protein: protein,
            carbs: carbs,
            fat: fat,
            fiber: fiber,
            note: note,
            photoPaths: paths,
            photoURLs: [],
            createdAt: createdAt,
            sourceId: "src-\(id)"
        )
    }

    func testEmptyStateWhenNoPhotos() async {
        let seed = [food(id: "n1", paths: [], on: today)]
        let (vm, _, photo) = makeVM(seed: seed)
        await vm.load()
        if case .empty(let snap) = vm.loadState {
            XCTAssertTrue(snap.items.isEmpty)
        } else {
            XCTFail("expected empty, got \(vm.loadState)")
        }
        XCTAssertEqual(photo.signedURLCallCount, 0)
        XCTAssertEqual(photo.uploadCallCount, 0)
    }

    func testMultiPhotoSameFoodAndSort() async {
        let seed = [
            food(
                id: "f1",
                paths: [
                    "\(userId)/2026-07-12/a.jpg",
                    "\(userId)/2026-07-12/b.jpg",
                ],
                on: "2026-07-12",
                name: "双图",
                createdAt: "2026-07-12T09:00:00Z"
            ),
            food(
                id: "f2",
                paths: ["\(userId)/2026-07-13/c.jpg"],
                on: "2026-07-13",
                name: "今天",
                createdAt: "2026-07-13T10:00:00Z"
            ),
        ]
        let (vm, foodRepo, photo) = makeVM(seed: seed)
        await vm.load()
        guard case .loaded(let snap) = vm.loadState else {
            return XCTFail("expected loaded \(vm.loadState)")
        }
        XCTAssertEqual(snap.items.count, 3)
        XCTAssertEqual(snap.items.first?.dateKey, "2026-07-13")
        XCTAssertEqual(snap.sections.map(\.dateKey), ["2026-07-13", "2026-07-12"])
        XCTAssertEqual(snap.sections[1].items.count, 2)
        XCTAssertEqual(foodRepo.fetchBetweenCallCount, 1)
        XCTAssertEqual(photo.signedURLCallCount, 1)
        XCTAssertEqual(photo.uploadCallCount, 0)
        XCTAssertEqual(foodRepo.createCallCount, 0)
        XCTAssertEqual(foodRepo.updateCallCount, 0)
    }

    func testDays7BoundsExcludesOlderPhotos() async {
        let seed = [
            food(id: "in", paths: ["\(userId)/2026-07-10/x.jpg"], on: "2026-07-10"),
            food(id: "out", paths: ["\(userId)/2026-07-01/y.jpg"], on: "2026-07-01"),
        ]
        let (vm, foodRepo, _) = makeVM(seed: seed)
        await vm.load() // default days7
        guard case .loaded(let snap) = vm.loadState else {
            return XCTFail("expected loaded")
        }
        XCTAssertEqual(snap.items.map(\.foodId), ["in"])
        XCTAssertEqual(foodRepo.lastFetchBetween?.0, "2026-07-07")
        XCTAssertEqual(foodRepo.lastFetchBetween?.1, "2026-07-13")
    }

    func testDays30Bounds() async {
        let seed = [
            food(id: "old", paths: ["\(userId)/2026-06-01/z.jpg"], on: "2026-06-01"),
            food(id: "in", paths: ["\(userId)/2026-06-20/z.jpg"], on: "2026-06-20"),
        ]
        let (vm, foodRepo, _) = makeVM(seed: seed)
        await vm.selectRange(.days30)
        guard case .loaded(let snap) = vm.loadState else {
            return XCTFail("expected loaded \(vm.loadState)")
        }
        XCTAssertEqual(snap.items.map(\.foodId), ["in"])
        XCTAssertEqual(foodRepo.lastFetchBetween?.0, "2026-06-14")
        XCTAssertEqual(foodRepo.lastFetchBetween?.1, "2026-07-13")
    }

    func testAllRangeCapsAt100() async {
        var seed: [FoodItem] = []
        for i in 0..<105 {
            // Spread across months so dateKeys sort newest first.
            let month = i < 50 ? 7 : 6
            let day = (i % 28) + 1
            let key = String(format: "2026-%02d-%02d", month, day)
            seed.append(food(
                id: "id-\(i)",
                paths: ["\(userId)/\(key)/p\(i).jpg"],
                on: key,
                createdAt: "\(key)T12:00:00Z"
            ))
        }
        let (vm, foodRepo, photo) = makeVM(seed: seed)
        await vm.selectRange(.all)
        guard case .loaded(let snap) = vm.loadState else {
            return XCTFail("expected loaded \(vm.loadState)")
        }
        XCTAssertEqual(snap.items.count, 100)
        XCTAssertTrue(snap.wasCapped)
        XCTAssertEqual(foodRepo.fetchBetweenCallCount, 0)
        // fetchAll used
        XCTAssertGreaterThan(photo.signedURLCallCount, 0)
        XCTAssertEqual(photo.lastSignedRequest?.paths.count, 100)
    }

    func testPartialSignFailureKeepsSuccesses() async {
        let pathOK = "\(userId)/2026-07-13/ok.jpg"
        let pathFail = "\(userId)/2026-07-13/fail.jpg"
        let seed = [
            food(id: "1", paths: [pathOK], on: today, name: "成功"),
            food(id: "2", paths: [pathFail], on: today, name: "失败"),
        ]
        let photo = MockMealPhotoRepository(sessionUserId: userId)
        photo.pathsFailingSign = [pathFail]
        let (vm, foodRepo, _) = makeVM(seed: seed, photo: photo)
        await vm.load()
        guard case .partial(let snap, let message) = vm.loadState else {
            return XCTFail("expected partial \(vm.loadState)")
        }
        XCTAssertEqual(snap.items.count, 2)
        XCTAssertTrue(snap.items.first(where: { $0.path == pathOK })?.hasDisplayURL == true)
        XCTAssertTrue(snap.items.first(where: { $0.path == pathFail })?.hasDisplayURL == false)
        XCTAssertEqual(snap.failedPaths, [pathFail])
        XCTAssertFalse(message.isEmpty)
        XCTAssertEqual(foodRepo.createCallCount, 0)
        XCTAssertEqual(foodRepo.updateCallCount, 0)
        XCTAssertEqual(photo.uploadCallCount, 0)
        XCTAssertTrue(photo.deletedPaths.isEmpty)
    }

    func testTotalSignFailureKeepsMetadata() async {
        let path = "\(userId)/2026-07-13/a.jpg"
        let seed = [food(id: "1", paths: [path], on: today, name: "保留")]
        let photo = MockMealPhotoRepository(sessionUserId: userId)
        photo.forcedError = AppError.network(message: "sign down")
        let (vm, _, _) = makeVM(seed: seed, photo: photo)
        await vm.load()
        guard case .partial(let snap, let message) = vm.loadState else {
            return XCTFail("expected partial \(vm.loadState)")
        }
        XCTAssertEqual(snap.items.count, 1)
        XCTAssertEqual(snap.items[0].name, "保留")
        XCTAssertFalse(snap.items[0].hasDisplayURL)
        XCTAssertFalse(message.contains("eyJ"))
        XCTAssertTrue(message.contains("sign") || message.contains("网络") || !message.isEmpty)
    }

    func testRetryResignsWithoutUpload() async {
        let pathFail = "\(userId)/2026-07-13/fail.jpg"
        let seed = [food(id: "1", paths: [pathFail], on: today)]
        let photo = MockMealPhotoRepository(sessionUserId: userId)
        photo.pathsFailingSign = [pathFail]
        let (vm, foodRepo, _) = makeVM(seed: seed, photo: photo)
        await vm.load()
        XCTAssertEqual(photo.signedURLCallCount, 1)
        if case .partial = vm.loadState {} else { XCTFail("expected partial") }

        photo.pathsFailingSign = []
        await vm.retry()
        XCTAssertEqual(photo.signedURLCallCount, 2)
        XCTAssertEqual(photo.uploadCallCount, 0)
        XCTAssertEqual(foodRepo.createCallCount, 0)
        XCTAssertEqual(foodRepo.updateCallCount, 0)
        if case .loaded(let snap) = vm.loadState {
            XCTAssertTrue(snap.items[0].hasDisplayURL)
        } else {
            XCTFail("expected loaded after retry \(vm.loadState)")
        }
    }

    func testSinglePathRetryUpdatesItem() async {
        let path = "\(userId)/2026-07-13/one.jpg"
        let seed = [food(id: "1", paths: [path], on: today, name: "单项")]
        let photo = MockMealPhotoRepository(sessionUserId: userId)
        photo.pathsFailingSign = [path]
        let (vm, foodRepo, _) = makeVM(seed: seed, photo: photo)
        await vm.load()
        let fetchAfterLoad = foodRepo.fetchBetweenCallCount
        guard case .partial(let snap, _) = vm.loadState else {
            return XCTFail("partial expected")
        }
        let item = snap.items[0]
        photo.pathsFailingSign = []
        await vm.retrySign(for: item)
        XCTAssertEqual(photo.signedURLCallCount, 2)
        XCTAssertEqual(photo.lastSignedRequest?.paths, [path])
        XCTAssertEqual(photo.uploadCallCount, 0)
        // Single-path retry must not re-fetch foods or write.
        XCTAssertEqual(foodRepo.fetchBetweenCallCount, fetchAfterLoad)
        XCTAssertEqual(foodRepo.createCallCount, 0)
        XCTAssertEqual(foodRepo.updateCallCount, 0)
        if case .loaded(let after) = vm.loadState {
            XCTAssertTrue(after.items[0].hasDisplayURL)
            XCTAssertEqual(after.items[0].name, "单项")
        } else {
            XCTFail("expected loaded \(vm.loadState)")
        }
    }

    func testCloseDetailClearsSelection() async {
        let path = "\(userId)/2026-07-13/d.jpg"
        let (vm, _, _) = makeVM(seed: [food(id: "1", paths: [path], on: today)])
        await vm.load()
        guard case .loaded(let snap) = vm.loadState else {
            return XCTFail("loaded")
        }
        vm.openDetail(snap.items[0])
        XCTAssertTrue(vm.isPresentingDetail)
        XCTAssertNotNil(vm.selectedItem)
        vm.closeDetail()
        XCTAssertFalse(vm.isPresentingDetail)
        XCTAssertNil(vm.selectedItem)
    }

    func testOpenDetailMapsFoodFields() async {
        let path = "\(userId)/2026-07-13/d.jpg"
        let seed = [
            food(
                id: "d1",
                paths: [path],
                on: today,
                name: "鸡胸",
                meal: .dinner,
                cal: 200,
                protein: 40,
                carbs: 5,
                fat: 4,
                fiber: 1,
                note: "水煮"
            ),
        ]
        let (vm, _, _) = makeVM(seed: seed)
        await vm.load()
        guard case .loaded(let snap) = vm.loadState else {
            return XCTFail("loaded")
        }
        vm.openDetail(snap.items[0])
        XCTAssertTrue(vm.isPresentingDetail)
        XCTAssertEqual(vm.selectedItem?.name, "鸡胸")
        XCTAssertEqual(vm.selectedItem?.meal, .dinner)
        XCTAssertEqual(vm.selectedItem?.dateKey, today)
        XCTAssertEqual(vm.selectedItem?.calories, 200)
        XCTAssertEqual(vm.selectedItem?.protein, 40)
        XCTAssertEqual(vm.selectedItem?.fiber, 1)
        XCTAssertEqual(vm.selectedItem?.note, "水煮")
        vm.closeDetail()
        XCTAssertFalse(vm.isPresentingDetail)
        XCTAssertNil(vm.selectedItem)
    }

    func testFoodFetchErrorWithoutSnapshotIsError() async {
        let (vm, foodRepo, _) = makeVM()
        foodRepo.forcedError = AppError.network(message: "offline")
        await vm.load()
        if case .error(let message) = vm.loadState {
            XCTAssertFalse(message.isEmpty)
            XCTAssertFalse(message.contains("eyJ"))
        } else {
            XCTFail("expected error \(vm.loadState)")
        }
    }

    func testDoesNotCallWriteAPIsOnLoad() async {
        let seed = [food(id: "1", paths: ["\(userId)/2026-07-13/a.jpg"], on: today)]
        let (vm, foodRepo, photo) = makeVM(seed: seed)
        await vm.load()
        XCTAssertEqual(foodRepo.createCallCount, 0)
        XCTAssertEqual(foodRepo.updateCallCount, 0)
        XCTAssertEqual(photo.uploadCallCount, 0)
        XCTAssertTrue(photo.deletedPaths.isEmpty)
        // delete is on food repo — MockFoodItemRepository has no deleteCallCount; ensure no crash.
        _ = vm
    }
}

final class MockMealPhotoPartialSignTests: XCTestCase {
    func testPathsFailingSignReturnNilURLWithoutThrowing() async throws {
        let userId = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        let ok = "\(userId)/d/ok.jpg"
        let bad = "\(userId)/d/bad.jpg"
        let repo = MockMealPhotoRepository(sessionUserId: userId)
        repo.pathsFailingSign = [bad]
        let refs = try await repo.signedURLs(
            for: SignedURLRequest(paths: [ok, bad], expiresIn: 60)
        )
        XCTAssertEqual(refs.count, 2)
        XCTAssertNotNil(refs[0].signedURL)
        XCTAssertNil(refs[1].signedURL)
    }
}
