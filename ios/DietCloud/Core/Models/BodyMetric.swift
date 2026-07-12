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
}
