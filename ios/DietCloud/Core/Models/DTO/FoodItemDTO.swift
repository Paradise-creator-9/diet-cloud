import Foundation

/// Postgres / PostgREST row for `food_items`.
struct FoodItemRow: Codable, Equatable, Sendable {
    var id: String?
    var user_id: String?
    var source_id: String?
    var eaten_on: String
    var meal: String
    var name: String
    var grams: Double?
    var calories: Double?
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    var fiber: Double?
    var note: String?
    var photo_urls: [String]?
    var created_at: String?
}

/// Insert/update body. Omits `user_id` so RLS / `default auth.uid()` owns identity.
struct FoodItemInsertPayload: Codable, Equatable, Sendable {
    var source_id: String?
    var eaten_on: String
    var meal: String
    var name: String
    var grams: Double
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var fiber: Double
    var note: String?
    var photo_urls: [String]
}

enum FoodItemMapper {
    static func domain(from row: FoodItemRow, photoURLs: [String]? = nil) throws -> FoodItem {
        guard let id = row.id, !id.isEmpty else {
            throw AppError.unknown(message: "food_items 行缺少 id。")
        }
        guard let meal = MealType(rawValue: row.meal) else {
            throw AppError.unknown(message: "未知 meal 类型。")
        }
        let paths = row.photo_urls ?? []
        return FoodItem(
            id: id,
            dateKey: row.eaten_on,
            meal: meal,
            name: row.name,
            grams: row.grams ?? 0,
            calories: row.calories ?? 0,
            protein: row.protein ?? 0,
            carbs: row.carbs ?? 0,
            fat: row.fat ?? 0,
            fiber: row.fiber ?? 0,
            note: row.note ?? "",
            photoPaths: paths,
            photoURLs: photoURLs ?? paths,
            createdAt: row.created_at ?? "",
            sourceId: row.source_id
        )
    }

    static func insertPayload(from write: FoodItemWrite, generatedSourceId: String?) -> FoodItemInsertPayload {
        let note = write.note.trimmingCharacters(in: .whitespacesAndNewlines)
        return FoodItemInsertPayload(
            source_id: write.sourceId ?? generatedSourceId,
            eaten_on: write.dateKey,
            meal: write.meal.rawValue,
            name: write.name.trimmingCharacters(in: .whitespacesAndNewlines),
            grams: max(0, write.grams),
            calories: max(0, write.calories),
            protein: max(0, write.protein),
            carbs: max(0, write.carbs),
            fat: max(0, write.fat),
            fiber: max(0, write.fiber),
            note: note.isEmpty ? nil : note,
            photo_urls: write.photoPaths
        )
    }

    /// Ensures encoded payload never contains a client-supplied foreign user_id key.
    static func assertPayloadHasNoUserId(_ payload: FoodItemInsertPayload) -> Bool {
        // Struct has no user_id property — compile-time guarantee; runtime check for JSON.
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(payload),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return obj["user_id"] == nil && obj["userId"] == nil
    }
}
