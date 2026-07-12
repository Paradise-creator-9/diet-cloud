import XCTest
@testable import DietCloud

final class FoodItemRepositoryTests: XCTestCase {
    private let userId = "11111111-1111-1111-1111-111111111111"

    func testFetchByDateKeyFiltersAndSorts() async throws {
        let repo = MockFoodItemRepository(sessionUserId: userId, seed: [
            makeItem(id: "2", date: "2026-07-12", created: "2026-07-12T10:00:00Z", name: "后"),
            makeItem(id: "1", date: "2026-07-12", created: "2026-07-12T08:00:00Z", name: "先"),
            makeItem(id: "3", date: "2026-07-11", created: "2026-07-11T08:00:00Z", name: "昨天"),
        ])
        let day = try await repo.fetchByDateKey("2026-07-12")
        XCTAssertEqual(day.map(\.name), ["先", "后"])
    }

    func testCreateUpdateDeleteFlow() async throws {
        let repo = MockFoodItemRepository(sessionUserId: userId)
        let created = try await repo.create(
            FoodItemWrite(dateKey: "2026-07-12", meal: .dinner, name: "西兰花", calories: 70, protein: 6)
        )
        XCTAssertEqual(repo.lastWriteSessionUserId, userId)
        XCTAssertEqual(created.name, "西兰花")

        let updated = try await repo.update(
            id: created.id,
            write: FoodItemWrite(dateKey: "2026-07-12", meal: .dinner, name: "西兰花加大", calories: 90, protein: 8)
        )
        XCTAssertEqual(updated.calories, 90)

        try await repo.delete(id: created.id)
        let remaining = try await repo.fetchByDateKey("2026-07-12")
        XCTAssertTrue(remaining.isEmpty)
    }

    func testNutritionSummaryLocal() async throws {
        let repo = MockFoodItemRepository(sessionUserId: userId)
        let items = [
            makeItem(id: "1", date: "2026-07-12", created: "a", name: "a", cal: 100, protein: 10),
            makeItem(id: "2", date: "2026-07-12", created: "b", name: "b", cal: 50, protein: 5),
        ]
        let summary = repo.nutritionSummary(for: items)
        XCTAssertEqual(summary.calories, 150)
        XCTAssertEqual(summary.protein, 15)
        XCTAssertEqual(DailyNutritionSummary.totals(for: items), summary)
    }

    func testCreatePayloadNeverAcceptsExternalUserId() async throws {
        let repo = MockFoodItemRepository(sessionUserId: userId)
        // Write type has no userId field — compile-time + runtime assert in create.
        _ = try await repo.create(
            FoodItemWrite(dateKey: "2026-07-12", meal: .snack, name: "香蕉")
        )
        XCTAssertEqual(repo.lastWriteSessionUserId, userId)
        XCTAssertNotEqual(repo.lastWriteSessionUserId, "attacker-id")
    }

    func testMealGroups() {
        let items = [
            makeItem(id: "1", date: "2026-07-12", created: "a", name: "蛋", meal: .breakfast),
            makeItem(id: "2", date: "2026-07-12", created: "b", name: "饭", meal: .lunch),
        ]
        let groups = DailyNutritionSummary.mealGroups(dateKey: "2026-07-12", items: items)
        XCTAssertEqual(groups.map(\.meal), [.breakfast, .lunch])
    }

    func testForcedErrorIsMappedByCallerSanitizer() async {
        let repo = MockFoodItemRepository(sessionUserId: userId)
        repo.forcedError = AppError.auth(.provider(message: "jwt eyJhbGciOiJIUzI1NiJ9.payload.sig leaked"))
        do {
            _ = try await repo.fetchByDateKey("2026-07-12")
            XCTFail("expected error")
        } catch {
            let mapped = DataErrorMapping.map(error)
            XCTAssertFalse(mapped.userMessage.contains("eyJ"))
        }
    }

    private func makeItem(
        id: String,
        date: String,
        created: String,
        name: String,
        meal: MealType = .breakfast,
        cal: Double = 0,
        protein: Double = 0
    ) -> FoodItem {
        FoodItem(
            id: id,
            dateKey: date,
            meal: meal,
            name: name,
            grams: 0,
            calories: cal,
            protein: protein,
            carbs: 0,
            fat: 0,
            fiber: 0,
            note: "",
            photoPaths: [],
            photoURLs: [],
            createdAt: created,
            sourceId: nil
        )
    }
}
