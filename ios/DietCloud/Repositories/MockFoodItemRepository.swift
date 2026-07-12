import Foundation

/// In-memory food repository for unit tests — no network / no secrets.
final class MockFoodItemRepository: FoodItemRepositoryProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [FoodItem] = []
    private let sessionUserId: String

    /// If set, create/update/delete throw this error.
    var forcedError: Error?

    /// Captured for tests asserting session ownership (never overwrites with external id).
    private(set) var lastWriteSessionUserId: String?

    init(sessionUserId: String = "11111111-1111-1111-1111-111111111111", seed: [FoodItem] = []) {
        self.sessionUserId = sessionUserId
        self.items = seed
    }

    func fetchAll() async throws -> [FoodItem] {
        try throwIfForced()
        return withLock { items.sorted { lhs, rhs in
            if lhs.dateKey != rhs.dateKey { return lhs.dateKey > rhs.dateKey }
            return lhs.createdAt < rhs.createdAt
        } }
    }

    func fetchByDateKey(_ dateKey: String) async throws -> [FoodItem] {
        try throwIfForced()
        return withLock {
            items
                .filter { $0.dateKey == dateKey }
                .sorted { $0.createdAt < $1.createdAt }
        }
    }

    func fetchById(_ id: String) async throws -> FoodItem? {
        try throwIfForced()
        return withLock { items.first { $0.id == id } }
    }

    func create(_ write: FoodItemWrite) async throws -> FoodItem {
        try throwIfForced()
        lastWriteSessionUserId = sessionUserId
        // Simulate payload without external userId — ownership is session only.
        let payload = FoodItemMapper.insertPayload(
            from: write,
            generatedSourceId: write.sourceId ?? "manual-\(UUID().uuidString.lowercased())"
        )
        precondition(FoodItemMapper.assertPayloadHasNoUserId(payload))
        let item = FoodItem(
            id: UUID().uuidString.lowercased(),
            dateKey: payload.eaten_on,
            meal: MealType(rawValue: payload.meal)!,
            name: payload.name,
            grams: payload.grams,
            calories: payload.calories,
            protein: payload.protein,
            carbs: payload.carbs,
            fat: payload.fat,
            fiber: payload.fiber,
            note: payload.note ?? "",
            photoPaths: payload.photo_urls,
            photoURLs: payload.photo_urls,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            sourceId: payload.source_id
        )
        withLock { items.append(item) }
        return item
    }

    func update(id: String, write: FoodItemWrite) async throws -> FoodItem {
        try throwIfForced()
        lastWriteSessionUserId = sessionUserId
        let payload = FoodItemMapper.insertPayload(from: write, generatedSourceId: write.sourceId)
        precondition(FoodItemMapper.assertPayloadHasNoUserId(payload))
        return try withLock {
            guard let index = items.firstIndex(where: { $0.id == id }) else {
                throw AppError.unknown(message: "记录不存在。")
            }
            let previous = items[index]
            let updated = FoodItem(
                id: previous.id,
                dateKey: payload.eaten_on,
                meal: MealType(rawValue: payload.meal)!,
                name: payload.name,
                grams: payload.grams,
                calories: payload.calories,
                protein: payload.protein,
                carbs: payload.carbs,
                fat: payload.fat,
                fiber: payload.fiber,
                note: payload.note ?? "",
                photoPaths: payload.photo_urls,
                photoURLs: payload.photo_urls,
                createdAt: previous.createdAt,
                sourceId: payload.source_id ?? previous.sourceId
            )
            items[index] = updated
            return updated
        }
    }

    func delete(id: String) async throws {
        try throwIfForced()
        lastWriteSessionUserId = sessionUserId
        withLock { items.removeAll { $0.id == id } }
    }

    func nutritionSummary(for items: [FoodItem]) -> DailyNutritionSummary {
        DailyNutritionSummary.totals(for: items)
    }

    private func throwIfForced() throws {
        if let forcedError { throw forcedError }
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}
