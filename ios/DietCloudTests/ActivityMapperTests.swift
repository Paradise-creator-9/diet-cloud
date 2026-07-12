import XCTest
@testable import DietCloud

final class ActivityMapperTests: XCTestCase {
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
