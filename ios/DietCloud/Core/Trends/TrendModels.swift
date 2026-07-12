import Foundation

/// Rolling window for the trends screen (includes today).
enum TrendRange: Int, CaseIterable, Identifiable, Sendable {
    case days7 = 7
    case days30 = 30

    var id: Int { rawValue }
    var dayCount: Int { rawValue }

    var title: String {
        switch self {
        case .days7: return "近 7 天"
        case .days30: return "近 30 天"
        }
    }
}

/// Nutrient series picker for nutrition charts (carbs shown but not used for goal-met).
enum TrendNutrientMetric: String, CaseIterable, Identifiable, Sendable {
    case protein
    case carbs
    case fiber

    var id: String { rawValue }

    var title: String {
        switch self {
        case .protein: return "蛋白质"
        case .carbs: return "碳水"
        case .fiber: return "膳食纤维"
        }
    }

    var unit: String { "g" }
}

enum TrendActivityMetric: String, CaseIterable, Identifiable, Sendable {
    case steps
    case activeCalories

    var id: String { rawValue }

    var title: String {
        switch self {
        case .steps: return "步数"
        case .activeCalories: return "活动消耗"
        }
    }
}

/// Per-day exercise rollup (sessions summed; not mixed into DailyActivity).
struct ExerciseDayTotals: Equatable, Sendable {
    var sessionCount: Int
    var durationMinutes: Double
    var activeCalories: Double

    static let zero = ExerciseDayTotals(sessionCount: 0, durationMinutes: 0, activeCalories: 0)
}

/// Composite goal status for the period summary.
enum TrendGoalMetStatus: Equatable, Sendable {
    /// None of calorie / protein / fiber goals are set.
    case notConfigured
    /// At least one of those goals is set; `metDays` among days with food.
    case configured(metDays: Int)
}

struct TrendPeriodSummary: Equatable, Sendable {
    /// Days with at least one food item.
    var foodRecordedDays: Int
    /// Average intake kcal over food-recorded days only (`nil` if none).
    var averageIntakeKcal: Double?
    var goalMet: TrendGoalMetStatus
    var exerciseSessionCount: Int
    var exerciseTotalMinutes: Double
}

/// Chart-ready optional point (missing days stay off the series).
struct TrendChartPoint: Equatable, Identifiable, Sendable {
    var dateKey: String
    var value: Double

    var id: String { dateKey }
}

/// Full aggregated snapshot for one range.
struct TrendSnapshot: Equatable, Sendable {
    var range: TrendRange
    /// Inclusive window keys, oldest → newest (length = range.dayCount).
    var dateKeys: [String]
    var startDateKey: String
    var endDateKey: String

    /// Days with food → nutrition totals (no synthetic zero days).
    var nutritionByDay: [String: DailyNutritionSummary]
    /// Days with weight → kg (latest record per day).
    var weightByDay: [String: Double]
    /// Days with a chosen daily activity (HealthKit preferred).
    var activityByDay: [String: DailyActivity]
    /// Days with ≥1 exercise session.
    var exerciseByDay: [String: ExerciseDayTotals]

    var summary: TrendPeriodSummary
    var calorieGoalKcal: Double?

    var hasAnyData: Bool {
        !nutritionByDay.isEmpty
            || !weightByDay.isEmpty
            || !activityByDay.isEmpty
            || !exerciseByDay.isEmpty
    }

    func intakePoints() -> [TrendChartPoint] {
        dateKeys.compactMap { key in
            guard let n = nutritionByDay[key] else { return nil }
            return TrendChartPoint(dateKey: key, value: n.calories)
        }
    }

    func nutrientPoints(_ metric: TrendNutrientMetric) -> [TrendChartPoint] {
        dateKeys.compactMap { key in
            guard let n = nutritionByDay[key] else { return nil }
            let value: Double
            switch metric {
            case .protein: value = n.protein
            case .carbs: value = n.carbs
            case .fiber: value = n.fiber
            }
            return TrendChartPoint(dateKey: key, value: value)
        }
    }

    func weightPoints() -> [TrendChartPoint] {
        dateKeys.compactMap { key in
            guard let w = weightByDay[key] else { return nil }
            return TrendChartPoint(dateKey: key, value: w)
        }
    }

    func activityPoints(_ metric: TrendActivityMetric) -> [TrendChartPoint] {
        dateKeys.compactMap { key in
            guard let a = activityByDay[key] else { return nil }
            let value: Double
            switch metric {
            case .steps: value = a.steps
            case .activeCalories: value = a.activeCalories
            }
            return TrendChartPoint(dateKey: key, value: value)
        }
    }
}

enum TrendsLoadState: Equatable, Sendable {
    case loading
    case loaded(TrendSnapshot)
    case partial(TrendSnapshot, failedSources: [String], message: String)
    case empty(TrendSnapshot)
    case error(String)
}
