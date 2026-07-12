import XCTest
@testable import DietCloud

final class FoodItemMapperTests: XCTestCase {
    func testRowToDomainHandlesNulls() throws {
        let row = FoodItemRow(
            id: "abc",
            user_id: "user-1",
            source_id: nil,
            eaten_on: "2026-07-12",
            meal: "breakfast",
            name: "燕麦",
            grams: nil,
            calories: nil,
            protein: nil,
            carbs: nil,
            fat: nil,
            fiber: nil,
            note: nil,
            photo_urls: nil,
            created_at: nil
        )
        let item = try FoodItemMapper.domain(from: row)
        XCTAssertEqual(item.id, "abc")
        XCTAssertEqual(item.dateKey, "2026-07-12")
        XCTAssertEqual(item.meal, .breakfast)
        XCTAssertEqual(item.grams, 0)
        XCTAssertEqual(item.calories, 0)
        XCTAssertEqual(item.note, "")
        XCTAssertEqual(item.photoPaths, [])
        XCTAssertEqual(item.createdAt, "")
    }

    func testInsertPayloadHasNoUserId() {
        let write = FoodItemWrite(
            dateKey: "2026-07-12",
            meal: .lunch,
            name: " 鸡胸 ",
            grams: 150,
            calories: 200,
            protein: 30,
            carbs: 0,
            fat: 5,
            fiber: 0,
            note: "  ",
            photoPaths: ["u/2026-07-12/a.jpg"]
        )
        let payload = FoodItemMapper.insertPayload(from: write, generatedSourceId: "manual-1")
        XCTAssertEqual(payload.name, "鸡胸")
        XCTAssertNil(payload.note)
        XCTAssertEqual(payload.source_id, "manual-1")
        XCTAssertTrue(FoodItemMapper.assertPayloadHasNoUserId(payload))
    }

    func testUnknownMealThrows() {
        let row = FoodItemRow(
            id: "1",
            eaten_on: "2026-07-12",
            meal: "brunch",
            name: "x"
        )
        XCTAssertThrowsError(try FoodItemMapper.domain(from: row))
    }

    func testMissingIdThrows() {
        let row = FoodItemRow(id: nil, eaten_on: "2026-07-12", meal: "snack", name: "x")
        XCTAssertThrowsError(try FoodItemMapper.domain(from: row))
    }
}
