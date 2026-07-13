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
        formDraft(
            dateKey: dateKey,
            weightKg: weightKg,
            bodyFatPercent: bodyFatPercent,
            bmi: nil,
            muscleKg: nil,
            boneMassKg: nil,
            waterPercent: nil,
            bmrKcal: nil,
            visceralFat: nil,
            note: note,
            measuredAt: nil,
            analysis: nil,
            existing: existing
        )
    }

    /// Form save including Stage 16 extended metrics.
    /// - Parameters:
    ///   - Optional metrics: when `nil`, keep `existing` (or 0); never invent AI zeros.
    ///   - `analysis`: optional last AI result for segment fields when present.
    static func formDraft(
        dateKey: String,
        weightKg: Double,
        bodyFatPercent: Double,
        bmi: Double?,
        muscleKg: Double?,
        boneMassKg: Double?,
        waterPercent: Double?,
        bmrKcal: Double?,
        visceralFat: Double?,
        note: String,
        measuredAt: String?,
        analysis: BodyAnalysisResult? = nil,
        existing: BodyMetric? = nil
    ) -> BodyMetricWrite {
        let measured: String = {
            if let measuredAt, !measuredAt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return measuredAt
            }
            if let existing, !existing.measuredAt.isEmpty {
                return existing.measuredAt
            }
            return "\(dateKey)T12:00:00"
        }()

        return BodyMetricWrite(
            dateKey: dateKey,
            measuredAt: measured,
            score: analysis?.score ?? existing?.score ?? 0,
            weightKg: weightKg,
            bmi: bmi ?? existing?.bmi ?? 0,
            bodyFatPercent: bodyFatPercent,
            bodyAge: analysis?.bodyAge ?? existing?.bodyAge ?? 0,
            bodyType: analysis?.bodyType ?? existing?.bodyType ?? "",
            muscleKg: muscleKg ?? existing?.muscleKg ?? 0,
            skeletalMuscleKg: analysis?.skeletalMuscleKg ?? existing?.skeletalMuscleKg ?? 0,
            boneMassKg: boneMassKg ?? existing?.boneMassKg ?? 0,
            waterPercent: waterPercent ?? existing?.waterPercent ?? 0,
            visceralFat: visceralFat ?? existing?.visceralFat ?? 0,
            bmrKcal: bmrKcal ?? existing?.bmrKcal ?? 0,
            proteinPercent: analysis?.proteinPercent ?? existing?.proteinPercent ?? 0,
            trunkFatPercent: analysis?.trunkFatPercent ?? existing?.trunkFatPercent ?? 0,
            trunkMuscleKg: analysis?.trunkMuscleKg ?? existing?.trunkMuscleKg ?? 0,
            leftArmFatPercent: analysis?.leftArmFatPercent ?? existing?.leftArmFatPercent ?? 0,
            leftArmMuscleKg: analysis?.leftArmMuscleKg ?? existing?.leftArmMuscleKg ?? 0,
            rightArmFatPercent: analysis?.rightArmFatPercent ?? existing?.rightArmFatPercent ?? 0,
            rightArmMuscleKg: analysis?.rightArmMuscleKg ?? existing?.rightArmMuscleKg ?? 0,
            leftLegFatPercent: analysis?.leftLegFatPercent ?? existing?.leftLegFatPercent ?? 0,
            leftLegMuscleKg: analysis?.leftLegMuscleKg ?? existing?.leftLegMuscleKg ?? 0,
            rightLegFatPercent: analysis?.rightLegFatPercent ?? existing?.rightLegFatPercent ?? 0,
            rightLegMuscleKg: analysis?.rightLegMuscleKg ?? existing?.rightLegMuscleKg ?? 0,
            note: note
        )
    }
}
