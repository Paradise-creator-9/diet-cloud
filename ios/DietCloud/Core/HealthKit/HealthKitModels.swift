import Foundation

enum HealthKitAuthStatus: Equatable, Sendable {
    case unavailable
    case notDetermined
    case denied
    case authorized
}

/// One workout sample from HealthKit (no PII beyond activity metrics).
struct HealthKitWorkoutSample: Equatable, Sendable, Identifiable {
    /// Stable HealthKit workout UUID string — used as `exercise_activities.external_id`.
    var externalId: String
    var type: String
    var title: String
    /// ISO-8601 start time when available.
    var startedAt: String
    var durationMinutes: Double
    var activeCalories: Double
    var distanceKm: Double

    var id: String { externalId }
}

/// Aggregated HealthKit samples for a single diary `dateKey`.
struct HealthKitDaySnapshot: Equatable, Sendable {
    var dateKey: String
    var steps: Double?
    var activeCalories: Double?
    var distanceKm: Double?
    var weightKg: Double?
    var bodyFatPercent: Double?
    var workouts: [HealthKitWorkoutSample]

    var hasAnyData: Bool {
        steps != nil
            || activeCalories != nil
            || distanceKm != nil
            || weightKg != nil
            || bodyFatPercent != nil
            || !workouts.isEmpty
    }

    var hasDailyActivityData: Bool {
        steps != nil || activeCalories != nil || distanceKm != nil
    }

    var hasBodyData: Bool {
        weightKg != nil || bodyFatPercent != nil
    }
}

/// Outcome of applying a HealthKit snapshot into app repositories.
struct HealthKitImportResult: Equatable, Sendable {
    var importedDaily: Bool
    var importedBody: Bool
    var importedWorkouts: Int
    var skippedWorkouts: Int
    var skippedDailyBecauseManual: Bool
    var skippedBodyBecauseManual: Bool
    var userMessage: String

    static func empty(message: String) -> HealthKitImportResult {
        HealthKitImportResult(
            importedDaily: false,
            importedBody: false,
            importedWorkouts: 0,
            skippedWorkouts: 0,
            skippedDailyBecauseManual: false,
            skippedBodyBecauseManual: false,
            userMessage: message
        )
    }
}

enum HealthKitError: Error, Equatable, Sendable {
    case unavailable
    case authorizationDenied
    case authorizationFailed
    case queryFailed
    case noData

    var userMessage: String {
        switch self {
        case .unavailable:
            return "此设备不支持 Apple 健康，或健康功能不可用。"
        case .authorizationDenied:
            return "未获得健康数据读取权限。请在系统设置 → 健康 → 数据访问与设备 中允许膳食志读取。"
        case .authorizationFailed:
            return "无法完成健康权限请求，请稍后重试。"
        case .queryFailed:
            return "读取健康数据失败，请稍后重试。"
        case .noData:
            return "所选日期在健康中没有可导入的数据。"
        }
    }
}
