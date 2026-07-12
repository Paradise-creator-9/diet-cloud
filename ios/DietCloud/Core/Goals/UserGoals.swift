import Foundation

/// Local nutrition / weight goals. Not stored in Supabase (no schema change).
struct UserGoals: Equatable, Codable, Sendable {
    /// Daily calorie target (kcal). `nil` = not set.
    var dailyCaloriesKcal: Double?
    /// Target body weight (kg).
    var targetWeightKg: Double?
    var proteinGrams: Double?
    var carbsGrams: Double?
    var fatGrams: Double?

    static let empty = UserGoals(
        dailyCaloriesKcal: nil,
        targetWeightKg: nil,
        proteinGrams: nil,
        carbsGrams: nil,
        fatGrams: nil
    )

    var hasAnyGoal: Bool {
        dailyCaloriesKcal != nil
            || targetWeightKg != nil
            || proteinGrams != nil
            || carbsGrams != nil
            || fatGrams != nil
    }

    var hasCalorieGoal: Bool {
        (dailyCaloriesKcal ?? 0) > 0
    }
}

enum UserGoalsValidation {
    /// Validates draft strings. Empty fields clear that goal (`nil`).
    /// Returns `(goals, nil)` on success, or `(nil, message)` on failure.
    static func validate(
        caloriesText: String,
        weightText: String,
        proteinText: String,
        carbsText: String,
        fatText: String
    ) -> (UserGoals?, String?) {
        do {
            let calories = try optionalPositive(caloriesText, name: "每日目标热量", allowZero: false)
            let weight = try optionalPositive(weightText, name: "目标体重", allowZero: false)
            let protein = try optionalNonNegative(proteinText, name: "蛋白质目标")
            let carbs = try optionalNonNegative(carbsText, name: "碳水目标")
            let fat = try optionalNonNegative(fatText, name: "脂肪目标")
            return (
                UserGoals(
                    dailyCaloriesKcal: calories,
                    targetWeightKg: weight,
                    proteinGrams: protein,
                    carbsGrams: carbs,
                    fatGrams: fat
                ),
                nil
            )
        } catch let message as ValidationMessage {
            return (nil, message.text)
        } catch {
            return (nil, "输入无效，请检查后重试。")
        }
    }

    private struct ValidationMessage: Error {
        let text: String
    }

    private static func optionalPositive(_ text: String, name: String, allowZero: Bool) throws -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        guard let value = Double(trimmed), value.isFinite else {
            throw ValidationMessage(text: "\(name)需为有效数字。")
        }
        if allowZero {
            if value < 0 { throw ValidationMessage(text: "\(name)不能为负数。") }
        } else {
            if value <= 0 { throw ValidationMessage(text: "\(name)需大于 0。") }
        }
        return value
    }

    private static func optionalNonNegative(_ text: String, name: String) throws -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        guard let value = Double(trimmed), value.isFinite else {
            throw ValidationMessage(text: "\(name)需为有效数字。")
        }
        if value < 0 {
            throw ValidationMessage(text: "\(name)不能为负数。")
        }
        return value
    }
}

/// Progress against optional goals for the day overview.
struct GoalsProgress: Equatable, Sendable {
    var intakeKcal: Double
    var netKcal: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var goals: UserGoals

    var intakeLine: String {
        if let goal = goals.dailyCaloriesKcal, goal > 0 {
            return "\(format(intakeKcal)) / \(format(goal)) kcal"
        }
        return "\(format(intakeKcal)) kcal"
    }

    var netLine: String {
        if let goal = goals.dailyCaloriesKcal, goal > 0 {
            return "\(format(netKcal)) / \(format(goal)) kcal"
        }
        return "\(format(netKcal)) kcal"
    }

    var proteinLine: String {
        if let goal = goals.proteinGrams {
            return "\(format(proteinG)) / \(format(goal)) g"
        }
        return "\(format(proteinG)) g"
    }

    var carbsLine: String {
        if let goal = goals.carbsGrams {
            return "\(format(carbsG)) / \(format(goal)) g"
        }
        return "\(format(carbsG)) g"
    }

    var fatLine: String {
        if let goal = goals.fatGrams {
            return "\(format(fatG)) / \(format(goal)) g"
        }
        return "\(format(fatG)) g"
    }

    /// Ring/bar fraction for intake vs calorie goal. Clamped to `0...1`.
    var intakeProgress: Double {
        Self.clampedRatio(current: intakeKcal, goal: goals.dailyCaloriesKcal)
    }

    /// Ring/bar fraction for net vs calorie goal. Clamped to `0...1`.
    /// Negative net uses 0 (under-eating after burn still shows empty ring fill).
    var netProgress: Double {
        Self.clampedRatio(current: max(0, netKcal), goal: goals.dailyCaloriesKcal)
    }

    var proteinProgress: Double {
        Self.clampedRatio(current: proteinG, goal: goals.proteinGrams)
    }

    var carbsProgress: Double {
        Self.clampedRatio(current: carbsG, goal: goals.carbsGrams)
    }

    var fatProgress: Double {
        Self.clampedRatio(current: fatG, goal: goals.fatGrams)
    }

    /// True when current exceeds goal (for tinting; progress itself stays ≤ 1).
    func isOverGoal(current: Double, goal: Double?) -> Bool {
        guard let goal, goal > 0, current.isFinite else { return false }
        return current > goal
    }

    /// Safe progress ratio for UI rings/bars. Always in `0...1`.
    /// - No goal / non-positive goal / non-finite current → `0`
    /// - Over goal → `1` (clamped)
    static func clampedRatio(current: Double, goal: Double?) -> Double {
        guard let goal, goal > 0, current.isFinite else { return 0 }
        let raw = current / goal
        if !raw.isFinite { return 0 }
        return min(1, max(0, raw))
    }

    private func format(_ value: Double) -> String {
        if !value.isFinite { return "0" }
        if value.rounded() == value { return String(Int(value)) }
        return String(format: "%.1f", value)
    }
}
