import Foundation

/// Local favorite-food template. Not stored in Supabase (no schema change).
/// Used only to create new `food_items` rows via `create` — never updates existing diary rows.
struct FavoriteFood: Equatable, Codable, Identifiable, Sendable {
    var id: String
    var name: String
    var meal: MealType
    var grams: Double
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var fiber: Double
    var note: String

    init(
        id: String = UUID().uuidString.lowercased(),
        name: String,
        meal: MealType = .breakfast,
        grams: Double = 0,
        calories: Double = 0,
        protein: Double = 0,
        carbs: Double = 0,
        fat: Double = 0,
        fiber: Double = 0,
        note: String = ""
    ) {
        self.id = id
        self.name = name
        self.meal = meal
        self.grams = grams
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.fiber = fiber
        self.note = note
    }

    /// Build a template from an existing diary food row (no photos / sourceId).
    static func fromFoodItem(_ item: FoodItem) -> FavoriteFood {
        FavoriteFood(
            name: item.name,
            meal: item.meal,
            grams: item.grams,
            calories: item.calories,
            protein: item.protein,
            carbs: item.carbs,
            fat: item.fat,
            fiber: item.fiber,
            note: item.note
        )
    }

    /// Payload for `foodRepository.create`. Never carries photo paths or sourceId.
    func makeCreateWrite(dateKey: String) -> FoodItemWrite {
        FoodItemWrite(
            dateKey: dateKey,
            meal: meal,
            name: name,
            grams: grams,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            fiber: fiber,
            note: note,
            photoPaths: [],
            sourceId: nil
        )
    }
}

enum FavoriteFoodValidation {
    /// Validates draft strings for a template.
    /// Empty numeric fields become `0`. Non-numeric or negative values fail.
    /// Returns `(favorite, nil)` on success, or `(nil, message)` on failure.
    static func validate(
        id: String?,
        nameText: String,
        meal: MealType,
        gramsText: String,
        caloriesText: String,
        proteinText: String,
        carbsText: String,
        fatText: String,
        fiberText: String,
        noteText: String
    ) -> (FavoriteFood?, String?) {
        let name = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            return (nil, "请填写食物名称。")
        }

        do {
            let grams = try parseNonNegative(gramsText, name: "份量")
            let calories = try parseNonNegative(caloriesText, name: "热量")
            let protein = try parseNonNegative(proteinText, name: "蛋白质")
            let carbs = try parseNonNegative(carbsText, name: "碳水")
            let fat = try parseNonNegative(fatText, name: "脂肪")
            let fiber = try parseNonNegative(fiberText, name: "膳食纤维")
            let favorite = FavoriteFood(
                id: id ?? UUID().uuidString.lowercased(),
                name: name,
                meal: meal,
                grams: grams,
                calories: calories,
                protein: protein,
                carbs: carbs,
                fat: fat,
                fiber: fiber,
                note: noteText.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            return (favorite, nil)
        } catch let message as ValidationMessage {
            return (nil, message.text)
        } catch {
            return (nil, "输入无效，请检查后重试。")
        }
    }

    private struct ValidationMessage: Error {
        let text: String
    }

    /// Empty → 0; invalid / negative → error.
    private static func parseNonNegative(_ text: String, name: String) throws -> Double {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return 0 }
        let normalized: String
        if trimmed.contains(","), !trimmed.contains(".") {
            normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        } else {
            normalized = trimmed
        }
        guard let value = Double(normalized), value.isFinite else {
            throw ValidationMessage(text: "\(name)需为有效数字。")
        }
        if value < 0 {
            throw ValidationMessage(text: "\(name)不能为负数。")
        }
        return value
    }
}
