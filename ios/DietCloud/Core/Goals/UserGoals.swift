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

    private func format(_ value: Double) -> String {
        if !value.isFinite { return "0" }
        if value.rounded() == value { return String(Int(value)) }
        return String(format: "%.1f", value)
    }
}
