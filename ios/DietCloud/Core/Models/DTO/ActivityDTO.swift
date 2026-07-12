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

/// Upsert payload. `user_id` only from session.
struct DailyActivityUpsertPayload: Codable, Equatable, Sendable {
    var user_id: String
    var activity_on: String
    var source: String
    var steps: Double
    var active_calories: Double
    var total_calories: Double
    var exercise_minutes: Double
    var stand_hours: Double
    var distance_km: Double
    var floors: Double
    var resting_heart_rate: Double
    var hrv_ms: Double
    var sleep_minutes: Double
    var note: String?
}

struct ExerciseActivityInsertPayload: Codable, Equatable, Sendable {
    var user_id: String
    var activity_on: String
    var started_at: String?
    var source: String
    var external_id: String?
    var type: String
    var title: String
    var duration_minutes: Double
    var distance_km: Double
    var active_calories: Double
    var avg_heart_rate: Double
    var max_heart_rate: Double
    var elevation_gain_m: Double
    var note: String?
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

    static func upsertPayload(from write: DailyActivityWrite, sessionUserId: String) -> DailyActivityUpsertPayload {
        let note = write.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = write.source.trimmingCharacters(in: .whitespacesAndNewlines)
        return DailyActivityUpsertPayload(
            user_id: sessionUserId,
            activity_on: write.dateKey,
            source: source.isEmpty ? "manual" : source,
            steps: max(0, write.steps),
            active_calories: max(0, write.activeCalories),
            total_calories: max(0, write.totalCalories),
            exercise_minutes: max(0, write.exerciseMinutes),
            stand_hours: max(0, write.standHours),
            distance_km: max(0, write.distanceKm),
            floors: max(0, write.floors),
            resting_heart_rate: max(0, write.restingHeartRate),
            hrv_ms: max(0, write.hrvMs),
            sleep_minutes: max(0, write.sleepMinutes),
            note: note.isEmpty ? nil : note
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

    static func insertPayload(from write: ExerciseActivityWrite, sessionUserId: String) -> ExerciseActivityInsertPayload {
        let note = write.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let started = write.startedAt.trimmingCharacters(in: .whitespacesAndNewlines)
        return ExerciseActivityInsertPayload(
            user_id: sessionUserId,
            activity_on: write.dateKey,
            started_at: started.isEmpty ? nil : started,
            source: write.source.isEmpty ? "manual" : write.source,
            external_id: write.externalId,
            type: write.type.isEmpty ? "其他" : write.type,
            title: write.title.isEmpty ? "运动" : write.title,
            duration_minutes: max(0, write.durationMinutes),
            distance_km: max(0, write.distanceKm),
            active_calories: max(0, write.activeCalories),
            avg_heart_rate: max(0, write.avgHeartRate),
            max_heart_rate: max(0, write.maxHeartRate),
            elevation_gain_m: max(0, write.elevationGainM),
            note: note.isEmpty ? nil : note
        )
    }
}
