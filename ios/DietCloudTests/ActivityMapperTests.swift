import XCTest
@testable import DietCloud

final class ActivityMapperTests: XCTestCase {
    func testDailyUpsertPayloadUsesSessionUserId() {
        let write = DailyActivityWrite.manual(dateKey: "2026-07-13", steps: 1000, activeCalories: 50)
        let session = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        let payload = DailyActivityMapper.upsertPayload(from: write, sessionUserId: session)
        XCTAssertEqual(payload.user_id, session)
        XCTAssertEqual(payload.activity_on, "2026-07-13")
        XCTAssertEqual(payload.source, "manual")
        XCTAssertEqual(payload.steps, 1000)
    }

    func testExerciseInsertPayloadUsesSessionUserId() {
        let write = ExerciseActivityWrite.manual(
            dateKey: "2026-07-13",
            type: "骑行",
            title: "Cycling",
            durationMinutes: 30,
            activeCalories: 250
        )
        let session = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        let payload = ExerciseActivityMapper.insertPayload(from: write, sessionUserId: session)
        XCTAssertEqual(payload.user_id, session)
        XCTAssertEqual(payload.activity_on, "2026-07-13")
        XCTAssertNil(payload.external_id)
        XCTAssertEqual(payload.duration_minutes, 30)
    }

    func testDailyActivityNulls() throws {
        let row = DailyActivityRow(
            id: "d1",
            activity_on: "2026-07-12",
            source: nil,
            steps: nil,
            raw_metrics: nil,
            note: nil,
            created_at: nil
        )
        let activity = try DailyActivityMapper.domain(from: row)
        XCTAssertEqual(activity.source, "manual")
        XCTAssertEqual(activity.steps, 0)
        XCTAssertTrue(activity.rawMetrics.isEmpty)
    }

    func testExerciseActivityTitleFallback() throws {
        let row = ExerciseActivityRow(
            id: "e1",
            activity_on: "2026-07-12",
            type: "跑步",
            title: nil
        )
        let exercise = try ExerciseActivityMapper.domain(from: row)
        XCTAssertEqual(exercise.title, "跑步")
        XCTAssertEqual(exercise.type, "跑步")
    }
}
