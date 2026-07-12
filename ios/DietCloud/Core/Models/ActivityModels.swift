import Foundation

/// Nested value in `daily_activities.raw_metrics` jsonb.
struct HealthMetricValue: Equatable, Sendable, Codable {
    var label: String
    var category: String
    var value: Double
    var unit: String
}

/// Maps `public.daily_activities` / Web `DailyActivity`.
struct DailyActivity: Equatable, Identifiable, Sendable {
    let id: String
    let dateKey: String
    let source: String
    let steps: Double
    let activeCalories: Double
    let totalCalories: Double
    let exerciseMinutes: Double
    let standHours: Double
    let distanceKm: Double
    let floors: Double
    let restingHeartRate: Double
    let hrvMs: Double
    let sleepMinutes: Double
    let rawMetrics: [String: HealthMetricValue]
    let note: String
    let createdAt: String
}

struct DailyActivityWrite: Equatable, Sendable {
    var dateKey: String
    var source: String
    var steps: Double
    var activeCalories: Double
    var totalCalories: Double
    var exerciseMinutes: Double
    var standHours: Double
    var distanceKm: Double
    var floors: Double
    var restingHeartRate: Double
    var hrvMs: Double
    var sleepMinutes: Double
    var rawMetrics: [String: HealthMetricValue]
    var note: String

    /// Manual iOS entry (source defaults to `manual` for unique index with date).
    static func manual(
        dateKey: String,
        steps: Double,
        activeCalories: Double = 0,
        distanceKm: Double = 0,
        note: String = "",
        existing: DailyActivity? = nil
    ) -> DailyActivityWrite {
        DailyActivityWrite(
            dateKey: dateKey,
            source: "manual",
            steps: steps,
            activeCalories: activeCalories,
            totalCalories: existing?.totalCalories ?? activeCalories,
            exerciseMinutes: existing?.exerciseMinutes ?? 0,
            standHours: existing?.standHours ?? 0,
            distanceKm: distanceKm,
            floors: existing?.floors ?? 0,
            restingHeartRate: existing?.restingHeartRate ?? 0,
            hrvMs: existing?.hrvMs ?? 0,
            sleepMinutes: existing?.sleepMinutes ?? 0,
            rawMetrics: existing?.rawMetrics ?? [:],
            note: note
        )
    }
}

/// Maps `public.exercise_activities` / Web `ExerciseActivity`.
struct ExerciseActivity: Equatable, Identifiable, Sendable {
    let id: String
    let dateKey: String
    let startedAt: String
    let source: String
    let externalId: String
    let type: String
    let title: String
    let durationMinutes: Double
    let distanceKm: Double
    let activeCalories: Double
    let avgHeartRate: Double
    let maxHeartRate: Double
    let elevationGainM: Double
    let note: String
    let createdAt: String
}

struct ExerciseActivityWrite: Equatable, Sendable {
    var dateKey: String
    var startedAt: String
    var source: String
    var externalId: String?
    var type: String
    var title: String
    var durationMinutes: Double
    var distanceKm: Double
    var activeCalories: Double
    var avgHeartRate: Double
    var maxHeartRate: Double
    var elevationGainM: Double
    var note: String

    static func manual(
        dateKey: String,
        type: String,
        title: String,
        durationMinutes: Double,
        activeCalories: Double,
        distanceKm: Double = 0,
        note: String = ""
    ) -> ExerciseActivityWrite {
        let cleanType = type.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return ExerciseActivityWrite(
            dateKey: dateKey,
            startedAt: "\(dateKey)T12:00:00",
            source: "manual",
            externalId: nil,
            type: cleanType.isEmpty ? "其他" : cleanType,
            title: cleanTitle.isEmpty ? (cleanType.isEmpty ? "运动" : cleanType) : cleanTitle,
            durationMinutes: durationMinutes,
            distanceKm: distanceKm,
            activeCalories: activeCalories,
            avgHeartRate: 0,
            maxHeartRate: 0,
            elevationGainM: 0,
            note: note
        )
    }
}

/// Day-level energy rollup for summary cards (selected date only).
struct DayEnergySummary: Equatable, Sendable {
    var foodIntakeKcal: Double
    var exerciseBurnKcal: Double
    var activityBurnKcal: Double
    var steps: Double
    var weightKg: Double?
    /// When daily activity is from HealthKit, active energy already includes workouts.
    /// Do **not** also subtract exercise calories (方案 B).
    var dailyActivitySource: String?

    /// Net kcal avoiding double-count of HealthKit active energy + workout calories.
    var netKcal: Double {
        if dailyActivitySource == "healthkit" {
            return foodIntakeKcal - activityBurnKcal
        }
        return foodIntakeKcal - exerciseBurnKcal - activityBurnKcal
    }

    static let zero = DayEnergySummary(
        foodIntakeKcal: 0,
        exerciseBurnKcal: 0,
        activityBurnKcal: 0,
        steps: 0,
        weightKg: nil,
        dailyActivitySource: nil
    )
}
