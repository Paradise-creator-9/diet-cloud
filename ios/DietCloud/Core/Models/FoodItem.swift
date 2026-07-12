import Foundation

/// Domain food row — maps to `public.food_items` (one row = one food, not one meal).
/// Aligns with Web `FoodItem` in `src/types.ts`.
struct FoodItem: Equatable, Identifiable, Sendable {
    let id: String
    /// `eaten_on` as `YYYY-MM-DD` (dateKey).
    let dateKey: String
    let meal: MealType
    let name: String
    let grams: Double
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let fiber: Double
    let note: String
    /// Storage object paths (DB `photo_urls`); not public HTTP URLs.
    let photoPaths: [String]
    /// Optional signed/display URLs resolved for UI (not persisted).
    let photoURLs: [String]
    let createdAt: String
    /// Present when loaded from DB; not required for local drafts.
    let sourceId: String?
}

/// Client-side grouping of food items for one meal slot on a day.
/// **Not a database table** — schema has no `meals` aggregate.
struct MealGroup: Equatable, Sendable {
    let dateKey: String
    let meal: MealType
    let items: [FoodItem]

    var summary: DailyNutritionSummary {
        DailyNutritionSummary.totals(for: items)
    }
}

/// Write input for insert/update. **Never** includes `userId` from the caller —
/// ownership always comes from the authenticated Supabase session / RLS defaults.
struct FoodItemWrite: Equatable, Sendable {
    var dateKey: String
    var meal: MealType
    var name: String
    var grams: Double
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var fiber: Double
    var note: String
    /// Paths already in Storage (or retained on update). Upload is stage 4.
    var photoPaths: [String]
    /// Optional idempotent source id; new inserts may generate `manual-<uuid>`.
    var sourceId: String?

    init(
        dateKey: String,
        meal: MealType,
        name: String,
        grams: Double = 0,
        calories: Double = 0,
        protein: Double = 0,
        carbs: Double = 0,
        fat: Double = 0,
        fiber: Double = 0,
        note: String = "",
        photoPaths: [String] = [],
        sourceId: String? = nil
    ) {
        self.dateKey = dateKey
        self.meal = meal
        self.name = name
        self.grams = grams
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.fiber = fiber
        self.note = note
        self.photoPaths = photoPaths
        self.sourceId = sourceId
    }
}
