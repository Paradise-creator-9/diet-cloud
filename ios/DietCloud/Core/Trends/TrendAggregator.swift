import Foundation

/// Pure aggregation for trends (no I/O). Safe for unit tests.
enum TrendAggregator {
    // MARK: - Window

    /// Inclusive date keys for a rolling window ending on `endDateKey` (typically today).
    /// Length == `range.dayCount`, oldest → newest.
    static func dateKeys(
        for range: TrendRange,
        endingOn endDateKey: String,
        calendar: DiaryCalendar
    ) -> [String] {
        let count = range.dayCount
        var keys: [String] = []
        keys.reserveCapacity(count)
        for offset in stride(from: -(count - 1), through: 0, by: 1) {
            guard let key = calendar.shiftingDateKey(endDateKey, byDays: offset) else {
                continue
            }
            keys.append(key)
        }
        return keys
    }

    static func startAndEndKeys(
        for range: TrendRange,
        endingOn endDateKey: String,
        calendar: DiaryCalendar
    ) -> (start: String, end: String)? {
        let keys = dateKeys(for: range, endingOn: endDateKey, calendar: calendar)
        guard let start = keys.first, let end = keys.last else { return nil }
        return (start, end)
    }

    // MARK: - Per-source collapse

    /// Group foods by day and sum with `DailyNutritionSummary.totals`.
    static func nutritionByDay(from foods: [FoodItem]) -> [String: DailyNutritionSummary] {
        var groups: [String: [FoodItem]] = [:]
        for item in foods {
            groups[item.dateKey, default: []].append(item)
        }
        var result: [String: DailyNutritionSummary] = [:]
        result.reserveCapacity(groups.count)
        for (key, items) in groups {
            result[key] = DailyNutritionSummary.totals(for: items)
        }
        return result
    }

    /// One weight per day: latest `createdAt` (lexicographic ISO-ish string compare).
    /// Ties break by higher `id`. Days without weightKg > 0 are skipped.
    static func weightByDay(from metrics: [BodyMetric]) -> [String: Double] {
        var best: [String: BodyMetric] = [:]
        for metric in metrics {
            guard metric.weightKg > 0 else { continue }
            if let existing = best[metric.dateKey] {
                if isNewer(metric, than: existing) {
                    best[metric.dateKey] = metric
                }
            } else {
                best[metric.dateKey] = metric
            }
        }
        return best.mapValues(\.weightKg)
    }

    /// HealthKit preferred over manual; never sum sources.
    static func activityByDay(from activities: [DailyActivity]) -> [String: DailyActivity] {
        var groups: [String: [DailyActivity]] = [:]
        for activity in activities {
            groups[activity.dateKey, default: []].append(activity)
        }
        var result: [String: DailyActivity] = [:]
        for (key, list) in groups {
            if let picked = pickPreferredActivity(list) {
                result[key] = picked
            }
        }
        return result
    }

    static func pickPreferredActivity(_ activities: [DailyActivity]) -> DailyActivity? {
        guard !activities.isEmpty else { return nil }
        let healthkit = activities.filter { $0.source.lowercased() == "healthkit" }
        if let preferred = healthkit.max(by: { isOlderActivity($0, than: $1) }) {
            return preferred
        }
        return activities.max(by: { isOlderActivity($0, than: $1) })
    }

    /// Sum sessions / duration / activeCalories per day (not merged into DailyActivity).
    static func exerciseByDay(from exercises: [ExerciseActivity]) -> [String: ExerciseDayTotals] {
        var result: [String: ExerciseDayTotals] = [:]
        for exercise in exercises {
            var totals = result[exercise.dateKey] ?? .zero
            totals.sessionCount += 1
            totals.durationMinutes += exercise.durationMinutes
            totals.activeCalories += exercise.activeCalories
            result[exercise.dateKey] = totals
        }
        return result
    }

    // MARK: - Goals

    /// Calorie band: intake within 90%…110% of goal (inclusive).
    static func isCalorieInBand(intake: Double, goal: Double) -> Bool {
        guard goal > 0, intake.isFinite, goal.isFinite else { return false }
        let lower = goal * 0.9
        let upper = goal * 1.1
        return intake + 1e-9 >= lower && intake - 1e-9 <= upper
    }

    static func isProteinMet(intake: Double, goal: Double?) -> Bool {
        guard let goal, goal >= 0, intake.isFinite else { return true }
        // Unset handled by caller; if goal present require ≥
        return intake + 1e-9 >= goal
    }

    static func isFiberMet(intake: Double, goal: Double?) -> Bool {
        guard let goal, goal >= 0, intake.isFinite else { return true }
        return intake + 1e-9 >= goal
    }

    /// Composite goal: only configured among calorie / protein / fiber.
    /// Day must have food. Carbs never participate.
    static func goalMetStatus(
        nutritionByDay: [String: DailyNutritionSummary],
        goals: UserGoals
    ) -> TrendGoalMetStatus {
        let calorieGoal = goals.dailyCaloriesKcal.flatMap { $0 > 0 ? $0 : nil }
        let proteinGoal = goals.proteinGrams
        let fiberGoal = goals.fiberGrams
        let anyConfigured = calorieGoal != nil || proteinGoal != nil || fiberGoal != nil
        guard anyConfigured else { return .notConfigured }

        var met = 0
        for (_, nutrition) in nutritionByDay {
            var dayOK = true
            if let calorieGoal {
                dayOK = dayOK && isCalorieInBand(intake: nutrition.calories, goal: calorieGoal)
            }
            if let proteinGoal {
                dayOK = dayOK && nutrition.protein + 1e-9 >= proteinGoal
            }
            if let fiberGoal {
                dayOK = dayOK && nutrition.fiber + 1e-9 >= fiberGoal
            }
            if dayOK { met += 1 }
        }
        return .configured(metDays: met)
    }

    // MARK: - Snapshot

    static func buildSnapshot(
        range: TrendRange,
        endDateKey: String,
        calendar: DiaryCalendar,
        foods: [FoodItem],
        bodyMetrics: [BodyMetric],
        activities: [DailyActivity],
        exercises: [ExerciseActivity],
        goals: UserGoals
    ) -> TrendSnapshot {
        let keys = dateKeys(for: range, endingOn: endDateKey, calendar: calendar)
        let start = keys.first ?? endDateKey
        let end = keys.last ?? endDateKey

        // Only keep points inside the window (repos should already filter).
        let keySet = Set(keys)
        let nutrition = nutritionByDay(from: foods).filter { keySet.contains($0.key) }
        let weights = weightByDay(from: bodyMetrics).filter { keySet.contains($0.key) }
        let activity = activityByDay(from: activities).filter { keySet.contains($0.key) }
        let exercise = exerciseByDay(from: exercises).filter { keySet.contains($0.key) }

        let foodDays = nutrition.count
        let avgIntake: Double?
        if foodDays > 0 {
            let sum = nutrition.values.reduce(0.0) { $0 + $1.calories }
            avgIntake = sum / Double(foodDays)
        } else {
            avgIntake = nil
        }

        let exerciseSessions = exercise.values.reduce(0) { $0 + $1.sessionCount }
        let exerciseMinutes = exercise.values.reduce(0.0) { $0 + $1.durationMinutes }

        let summary = TrendPeriodSummary(
            foodRecordedDays: foodDays,
            averageIntakeKcal: avgIntake,
            goalMet: goalMetStatus(nutritionByDay: nutrition, goals: goals),
            exerciseSessionCount: exerciseSessions,
            exerciseTotalMinutes: exerciseMinutes
        )

        return TrendSnapshot(
            range: range,
            dateKeys: keys,
            startDateKey: start,
            endDateKey: end,
            nutritionByDay: nutrition,
            weightByDay: weights,
            activityByDay: activity,
            exerciseByDay: exercise,
            summary: summary,
            calorieGoalKcal: goals.dailyCaloriesKcal.flatMap { $0 > 0 ? $0 : nil }
        )
    }

    // MARK: - Helpers

    private static func isNewer(_ lhs: BodyMetric, than rhs: BodyMetric) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.id > rhs.id
    }

    private static func isOlderActivity(_ lhs: DailyActivity, than rhs: DailyActivity) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id < rhs.id
    }
}
