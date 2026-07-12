import Foundation

/// Local aggregation of food items for a day — Web `DailyTotals` / `totalsFor()`.
struct DailyNutritionSummary: Equatable, Sendable {
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var fiber: Double
    var grams: Double

    static let zero = DailyNutritionSummary(
        calories: 0, protein: 0, carbs: 0, fat: 0, fiber: 0, grams: 0
    )

    static func totals(for items: [FoodItem]) -> DailyNutritionSummary {
        items.reduce(into: .zero) { sum, item in
            sum.calories += item.calories
            sum.protein += item.protein
            sum.carbs += item.carbs
            sum.fat += item.fat
            sum.fiber += item.fiber
            sum.grams += item.grams
        }
    }

    /// Group items by meal type in Web display order.
    static func mealGroups(dateKey: String, items: [FoodItem]) -> [MealGroup] {
        MealType.displayOrder.compactMap { meal in
            let filtered = items.filter { $0.meal == meal && $0.dateKey == dateKey }
            guard !filtered.isEmpty else { return nil }
            return MealGroup(dateKey: dateKey, meal: meal, items: filtered)
        }
    }
}
