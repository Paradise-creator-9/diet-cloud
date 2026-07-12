import XCTest
@testable import DietCloud

final class BodyMetricMapperTests: XCTestCase {
    func testUpsertPayloadUsesOnlySessionUserId() {
        let write = BodyMetricWrite(
            dateKey: "2026-07-12",
            measuredAt: "2026-07-12T08:00",
            score: 70,
            weightKg: 70,
            bmi: 22,
            bodyFatPercent: 15,
            bodyAge: 30,
            bodyType: "标准",
            muscleKg: 30,
            skeletalMuscleKg: 28,
            boneMassKg: 3,
            waterPercent: 50,
            visceralFat: 8,
            bmrKcal: 1500,
            proteinPercent: 18,
            trunkFatPercent: 0,
            trunkMuscleKg: 0,
            leftArmFatPercent: 0,
            leftArmMuscleKg: 0,
            rightArmFatPercent: 0,
            rightArmMuscleKg: 0,
            leftLegFatPercent: 0,
            leftLegMuscleKg: 0,
            rightLegFatPercent: 0,
            rightLegMuscleKg: 0,
            note: ""
        )
        let session = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        let payload = BodyMetricMapper.upsertPayload(from: write, sessionUserId: session)
        XCTAssertEqual(payload.user_id, session)
        XCTAssertEqual(payload.measured_at, "2026-07-12T08:00:00")
        XCTAssertNil(payload.note)
        // Attacker-supplied alternate id is impossible — only sessionUserId param is used.
        let other = BodyMetricMapper.upsertPayload(from: write, sessionUserId: "other-user")
        XCTAssertEqual(other.user_id, "other-user")
        XCTAssertNotEqual(other.user_id, session)
    }

    func testRowNullsDefaultToZero() throws {
        let row = BodyMetricRow(
            id: "m1",
            measured_on: "2026-07-01",
            measured_at: nil,
            score: nil,
            weight_kg: nil,
            note: nil,
            created_at: nil
        )
        let metric = try BodyMetricMapper.domain(from: row)
        XCTAssertEqual(metric.weightKg, 0)
        XCTAssertEqual(metric.note, "")
        XCTAssertEqual(metric.measuredAt, "")
    }
}
