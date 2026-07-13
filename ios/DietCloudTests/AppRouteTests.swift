import UserNotifications
import XCTest
@testable import DietCloud

final class AppRouteTests: XCTestCase {
    override func setUp() {
        super.setUp()
        PendingDeepLinkStore.shared.resetForTests()
    }

    override func tearDown() {
        PendingDeepLinkStore.shared.resetForTests()
        super.tearDown()
    }

    func testReminderKindsMapToRoutes() {
        XCTAssertEqual(ReminderKind.breakfast.appRoute, .addMeal(.breakfast))
        XCTAssertEqual(ReminderKind.lunch.appRoute, .addMeal(.lunch))
        XCTAssertEqual(ReminderKind.dinner.appRoute, .addMeal(.dinner))
        XCTAssertEqual(ReminderKind.weighIn.appRoute, .bodyMetric)
        XCTAssertEqual(ReminderKind.dailySummary.appRoute, .homeToday)
    }

    func testUserInfoRoundTrip() {
        for kind in ReminderKind.allCases {
            let info = ReminderUserInfo.make(kind: kind)
            let route = ReminderUserInfo.route(fromUserInfo: info, identifier: nil)
            XCTAssertEqual(route, kind.appRoute, "kind \(kind)")
        }
    }

    func testRouteFallsBackToIdentifier() {
        let route = ReminderUserInfo.route(
            fromUserInfo: [:],
            identifier: ReminderKind.weighIn.notificationIdentifier
        )
        XCTAssertEqual(route, .bodyMetric)
    }

    func testUnknownIdentifierReturnsNil() {
        XCTAssertNil(ReminderUserInfo.route(fromUserInfo: nil, identifier: "other.app.notification"))
    }

    func testDefaultNotificationActionConstant() {
        // Documented contract: only UNNotificationDefaultActionIdentifier should route.
        XCTAssertEqual(UNNotificationDefaultActionIdentifier, "com.apple.UNNotificationDefaultActionIdentifier")
    }

    func testPendingStoreConsumeOnce() {
        PendingDeepLinkStore.shared.set(.addMeal(.lunch))
        XCTAssertEqual(PendingDeepLinkStore.shared.peekForTests(), .addMeal(.lunch))
        XCTAssertEqual(PendingDeepLinkStore.shared.consume(), .addMeal(.lunch))
        XCTAssertNil(PendingDeepLinkStore.shared.consume())
        XCTAssertNil(PendingDeepLinkStore.shared.peekForTests())
    }

    func testPendingStoreLatestWins() {
        PendingDeepLinkStore.shared.set(.homeToday)
        PendingDeepLinkStore.shared.set(.bodyMetric)
        XCTAssertEqual(PendingDeepLinkStore.shared.consume(), .bodyMetric)
    }
}

@MainActor
final class ReminderRouteViewModelTests: XCTestCase {
    private let user = AuthUser(id: "11111111-1111-1111-1111-111111111111", email: "a@example.com")
    private let dateKey = "2026-07-13"

    override func setUp() {
        super.setUp()
        PendingDeepLinkStore.shared.resetForTests()
    }

    override func tearDown() {
        PendingDeepLinkStore.shared.resetForTests()
        super.tearDown()
    }

    private func makeVM(dateKey: String? = nil) -> TodayMealsViewModel {
        let photo = MockMealPhotoRepository(sessionUserId: user.id)
        let food = MockFoodItemRepository(sessionUserId: user.id, photoRepository: photo)
        return TodayMealsViewModel(
            user: user,
            foodRepository: food,
            photoRepository: photo,
            analyzeAPI: MockAnalyzeAPIClient(),
            diaryCalendar: DiaryCalendar.tokyo(),
            dateKey: dateKey ?? self.dateKey
        )
    }

    func testApplyRouteBreakfastOpensAddSheetWithMeal() async {
        let vm = makeVM()
        await vm.applyRoute(.addMeal(.breakfast))
        XCTAssertTrue(vm.isPresentingAddSheet)
        XCTAssertFalse(vm.isEditingFood)
        XCTAssertEqual(vm.draftMeal, .breakfast)
        XCTAssertTrue(vm.isToday || vm.selectedDateKey == DiaryCalendar.tokyo().dateKey(from: Date()))
    }

    func testApplyRouteWeighInOpensBodySheet() async {
        let vm = makeVM(dateKey: "2026-07-01")
        await vm.applyRoute(.bodyMetric)
        XCTAssertTrue(vm.isPresentingBodySheet)
        XCTAssertFalse(vm.isPresentingAddSheet)
        XCTAssertTrue(vm.isToday)
    }

    func testApplyRouteHomeTodayGoesTodayWithoutSheets() async {
        let vm = makeVM(dateKey: "2026-07-01")
        vm.openAddSheet()
        await vm.applyRoute(.homeToday)
        XCTAssertTrue(vm.isToday)
        XCTAssertFalse(vm.isPresentingAddSheet)
        XCTAssertFalse(vm.isPresentingBodySheet)
    }

    func testConsumePendingRouteOnceAfterLoginSimulation() async {
        PendingDeepLinkStore.shared.set(.addMeal(.dinner))
        let vm = makeVM()
        await vm.consumePendingRouteIfNeeded()
        XCTAssertTrue(vm.isPresentingAddSheet)
        XCTAssertEqual(vm.draftMeal, .dinner)
        await vm.consumePendingRouteIfNeeded()
        // Second consume is a no-op; sheet may still be open from first.
        XCTAssertNil(PendingDeepLinkStore.shared.peekForTests())
    }

    func testForegroundNotificationTapSetsPendingThenConsume() async {
        // Simulate delegate writing pending while already signed in.
        PendingDeepLinkStore.shared.set(.addMeal(.lunch))
        let vm = makeVM()
        await vm.consumePendingRouteIfNeeded()
        XCTAssertEqual(vm.draftMeal, .lunch)
        XCTAssertTrue(vm.isPresentingAddSheet)
    }
}
