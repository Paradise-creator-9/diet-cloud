import Foundation

struct BodyMetricRow: Codable, Equatable, Sendable {
    var id: String?
    var user_id: String?
    var measured_on: String
    var measured_at: String?
    var score: Double?
    var weight_kg: Double?
    var bmi: Double?
    var body_fat_percent: Double?
    var body_age: Double?
    var body_type: String?
    var muscle_kg: Double?
    var skeletal_muscle_kg: Double?
    var bone_mass_kg: Double?
    var water_percent: Double?
    var visceral_fat: Double?
    var bmr_kcal: Double?
    var protein_percent: Double?
    var trunk_fat_percent: Double?
    var trunk_muscle_kg: Double?
    var left_arm_fat_percent: Double?
    var left_arm_muscle_kg: Double?
    var right_arm_fat_percent: Double?
    var right_arm_muscle_kg: Double?
    var left_leg_fat_percent: Double?
    var left_leg_muscle_kg: Double?
    var right_leg_fat_percent: Double?
    var right_leg_muscle_kg: Double?
    var note: String?
    var created_at: String?
}

/// Upsert payload. `user_id` is set only by repository from session.
struct BodyMetricUpsertPayload: Codable, Equatable, Sendable {
    var user_id: String
    var measured_on: String
    var measured_at: String?
    var score: Double
    var weight_kg: Double
    var bmi: Double
    var body_fat_percent: Double
    var body_age: Double
    var body_type: String?
    var muscle_kg: Double
    var skeletal_muscle_kg: Double
    var bone_mass_kg: Double
    var water_percent: Double
    var visceral_fat: Double
    var bmr_kcal: Double
    var protein_percent: Double
    var trunk_fat_percent: Double
    var trunk_muscle_kg: Double
    var left_arm_fat_percent: Double
    var left_arm_muscle_kg: Double
    var right_arm_fat_percent: Double
    var right_arm_muscle_kg: Double
    var left_leg_fat_percent: Double
    var left_leg_muscle_kg: Double
    var right_leg_fat_percent: Double
    var right_leg_muscle_kg: Double
    var note: String?
}

enum BodyMetricMapper {
    static func domain(from row: BodyMetricRow) throws -> BodyMetric {
        guard let id = row.id, !id.isEmpty else {
            throw AppError.unknown(message: "body_metrics 行缺少 id。")
        }
        return BodyMetric(
            id: id,
            dateKey: row.measured_on,
            measuredAt: row.measured_at ?? "",
            score: row.score ?? 0,
            weightKg: row.weight_kg ?? 0,
            bmi: row.bmi ?? 0,
            bodyFatPercent: row.body_fat_percent ?? 0,
            bodyAge: row.body_age ?? 0,
            bodyType: row.body_type ?? "",
            muscleKg: row.muscle_kg ?? 0,
            skeletalMuscleKg: row.skeletal_muscle_kg ?? 0,
            boneMassKg: row.bone_mass_kg ?? 0,
            waterPercent: row.water_percent ?? 0,
            visceralFat: row.visceral_fat ?? 0,
            bmrKcal: row.bmr_kcal ?? 0,
            proteinPercent: row.protein_percent ?? 0,
            trunkFatPercent: row.trunk_fat_percent ?? 0,
            trunkMuscleKg: row.trunk_muscle_kg ?? 0,
            leftArmFatPercent: row.left_arm_fat_percent ?? 0,
            leftArmMuscleKg: row.left_arm_muscle_kg ?? 0,
            rightArmFatPercent: row.right_arm_fat_percent ?? 0,
            rightArmMuscleKg: row.right_arm_muscle_kg ?? 0,
            leftLegFatPercent: row.left_leg_fat_percent ?? 0,
            leftLegMuscleKg: row.left_leg_muscle_kg ?? 0,
            rightLegFatPercent: row.right_leg_fat_percent ?? 0,
            rightLegMuscleKg: row.right_leg_muscle_kg ?? 0,
            note: row.note ?? "",
            createdAt: row.created_at ?? ""
        )
    }

    static func upsertPayload(from write: BodyMetricWrite, sessionUserId: String) -> BodyMetricUpsertPayload {
        let measuredAt: String
        if write.measuredAt.isEmpty {
            measuredAt = "\(write.dateKey)T00:00:00"
        } else if write.measuredAt.count == 16 {
            measuredAt = "\(write.measuredAt):00"
        } else {
            measuredAt = write.measuredAt
        }
        let bodyType = write.bodyType.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = write.note.trimmingCharacters(in: .whitespacesAndNewlines)
        return BodyMetricUpsertPayload(
            user_id: sessionUserId,
            measured_on: write.dateKey,
            measured_at: measuredAt,
            score: max(0, write.score),
            weight_kg: max(0, write.weightKg),
            bmi: max(0, write.bmi),
            body_fat_percent: max(0, write.bodyFatPercent),
            body_age: max(0, write.bodyAge),
            body_type: bodyType.isEmpty ? nil : bodyType,
            muscle_kg: max(0, write.muscleKg),
            skeletal_muscle_kg: max(0, write.skeletalMuscleKg),
            bone_mass_kg: max(0, write.boneMassKg),
            water_percent: max(0, write.waterPercent),
            visceral_fat: max(0, write.visceralFat),
            bmr_kcal: max(0, write.bmrKcal),
            protein_percent: max(0, write.proteinPercent),
            trunk_fat_percent: max(0, write.trunkFatPercent),
            trunk_muscle_kg: max(0, write.trunkMuscleKg),
            left_arm_fat_percent: max(0, write.leftArmFatPercent),
            left_arm_muscle_kg: max(0, write.leftArmMuscleKg),
            right_arm_fat_percent: max(0, write.rightArmFatPercent),
            right_arm_muscle_kg: max(0, write.rightArmMuscleKg),
            left_leg_fat_percent: max(0, write.leftLegFatPercent),
            left_leg_muscle_kg: max(0, write.leftLegMuscleKg),
            right_leg_fat_percent: max(0, write.rightLegFatPercent),
            right_leg_muscle_kg: max(0, write.rightLegMuscleKg),
            note: note.isEmpty ? nil : note
        )
    }
}
