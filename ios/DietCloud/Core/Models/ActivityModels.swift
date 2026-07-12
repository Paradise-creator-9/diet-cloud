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
}
