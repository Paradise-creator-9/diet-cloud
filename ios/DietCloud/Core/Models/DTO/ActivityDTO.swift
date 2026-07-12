import Foundation

struct DailyActivityRow: Codable, Equatable, Sendable {
    var id: String?
    var user_id: String?
    var activity_on: String
    var source: String?
    var steps: Double?
    var active_calories: Double?
    var total_calories: Double?
    var exercise_minutes: Double?
    var stand_hours: Double?
    var distance_km: Double?
    var floors: Double?
    var resting_heart_rate: Double?
    var hrv_ms: Double?
    var sleep_minutes: Double?
    var raw_metrics: [String: HealthMetricValue]?
    var note: String?
    var created_at: String?
}

struct ExerciseActivityRow: Codable, Equatable, Sendable {
    var id: String?
    var user_id: String?
    var activity_on: String
    var started_at: String?
    var source: String?
    var external_id: String?
    var type: String?
    var title: String?
    var duration_minutes: Double?
    var distance_km: Double?
    var active_calories: Double?
    var avg_heart_rate: Double?
    var max_heart_rate: Double?
    var elevation_gain_m: Double?
    var note: String?
    var created_at: String?
}

enum DailyActivityMapper {
    static func domain(from row: DailyActivityRow) throws -> DailyActivity {
        guard let id = row.id, !id.isEmpty else {
            throw AppError.unknown(message: "daily_activities 行缺少 id。")
        }
        return DailyActivity(
            id: id,
            dateKey: row.activity_on,
            source: row.source ?? "manual",
            steps: row.steps ?? 0,
            activeCalories: row.active_calories ?? 0,
            totalCalories: row.total_calories ?? 0,
            exerciseMinutes: row.exercise_minutes ?? 0,
            standHours: row.stand_hours ?? 0,
            distanceKm: row.distance_km ?? 0,
            floors: row.floors ?? 0,
            restingHeartRate: row.resting_heart_rate ?? 0,
            hrvMs: row.hrv_ms ?? 0,
            sleepMinutes: row.sleep_minutes ?? 0,
            rawMetrics: row.raw_metrics ?? [:],
            note: row.note ?? "",
            createdAt: row.created_at ?? ""
        )
    }
}

enum ExerciseActivityMapper {
    static func domain(from row: ExerciseActivityRow) throws -> ExerciseActivity {
        guard let id = row.id, !id.isEmpty else {
            throw AppError.unknown(message: "exercise_activities 行缺少 id。")
        }
        let type = row.type ?? "其他"
        return ExerciseActivity(
            id: id,
            dateKey: row.activity_on,
            startedAt: row.started_at ?? "",
            source: row.source ?? "manual",
            externalId: row.external_id ?? "",
            type: type,
            title: row.title ?? type,
            durationMinutes: row.duration_minutes ?? 0,
            distanceKm: row.distance_km ?? 0,
            activeCalories: row.active_calories ?? 0,
            avgHeartRate: row.avg_heart_rate ?? 0,
            maxHeartRate: row.max_heart_rate ?? 0,
            elevationGainM: row.elevation_gain_m ?? 0,
            note: row.note ?? "",
            createdAt: row.created_at ?? ""
        )
    }
}
