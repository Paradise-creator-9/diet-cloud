import Foundation

/// Maps `public.body_metrics` / Web `BodyMetric`.
struct BodyMetric: Equatable, Identifiable, Sendable {
    let id: String
    let dateKey: String
    let measuredAt: String
    let score: Double
    let weightKg: Double
    let bmi: Double
    let bodyFatPercent: Double
    let bodyAge: Double
    let bodyType: String
    let muscleKg: Double
    let skeletalMuscleKg: Double
    let boneMassKg: Double
    let waterPercent: Double
    let visceralFat: Double
    let bmrKcal: Double
    let proteinPercent: Double
    let trunkFatPercent: Double
    let trunkMuscleKg: Double
    let leftArmFatPercent: Double
    let leftArmMuscleKg: Double
    let rightArmFatPercent: Double
    let rightArmMuscleKg: Double
    let leftLegFatPercent: Double
    let leftLegMuscleKg: Double
    let rightLegFatPercent: Double
    let rightLegMuscleKg: Double
    let note: String
    let createdAt: String
}

/// Write payload for upsert. `userId` is never accepted from UI — repository injects session user.
struct BodyMetricWrite: Equatable, Sendable {
    var dateKey: String
    var measuredAt: String
    var score: Double
    var weightKg: Double
    var bmi: Double
    var bodyFatPercent: Double
    var bodyAge: Double
    var bodyType: String
    var muscleKg: Double
    var skeletalMuscleKg: Double
    var boneMassKg: Double
    var waterPercent: Double
    var visceralFat: Double
    var bmrKcal: Double
    var proteinPercent: Double
    var trunkFatPercent: Double
    var trunkMuscleKg: Double
    var leftArmFatPercent: Double
    var leftArmMuscleKg: Double
    var rightArmFatPercent: Double
    var rightArmMuscleKg: Double
    var leftLegFatPercent: Double
    var leftLegMuscleKg: Double
    var rightLegFatPercent: Double
    var rightLegMuscleKg: Double
    var note: String

    /// Manual entry for iOS UI — preserves segment fields when editing an existing row.
    static func manual(
        dateKey: String,
        weightKg: Double,
        bodyFatPercent: Double = 0,
        note: String = "",
        existing: BodyMetric? = nil
    ) -> BodyMetricWrite {
        BodyMetricWrite(
            dateKey: dateKey,
            measuredAt: existing?.measuredAt.isEmpty == false
                ? existing!.measuredAt
                : "\(dateKey)T12:00:00",
            score: existing?.score ?? 0,
            weightKg: weightKg,
            bmi: existing?.bmi ?? 0,
            bodyFatPercent: bodyFatPercent,
            bodyAge: existing?.bodyAge ?? 0,
            bodyType: existing?.bodyType ?? "",
            muscleKg: existing?.muscleKg ?? 0,
            skeletalMuscleKg: existing?.skeletalMuscleKg ?? 0,
            boneMassKg: existing?.boneMassKg ?? 0,
            waterPercent: existing?.waterPercent ?? 0,
            visceralFat: existing?.visceralFat ?? 0,
            bmrKcal: existing?.bmrKcal ?? 0,
            proteinPercent: existing?.proteinPercent ?? 0,
            trunkFatPercent: existing?.trunkFatPercent ?? 0,
            trunkMuscleKg: existing?.trunkMuscleKg ?? 0,
            leftArmFatPercent: existing?.leftArmFatPercent ?? 0,
            leftArmMuscleKg: existing?.leftArmMuscleKg ?? 0,
            rightArmFatPercent: existing?.rightArmFatPercent ?? 0,
            rightArmMuscleKg: existing?.rightArmMuscleKg ?? 0,
            leftLegFatPercent: existing?.leftLegFatPercent ?? 0,
            leftLegMuscleKg: existing?.leftLegMuscleKg ?? 0,
            rightLegFatPercent: existing?.rightLegFatPercent ?? 0,
            rightLegMuscleKg: existing?.rightLegMuscleKg ?? 0,
            note: note
        )
    }
}
