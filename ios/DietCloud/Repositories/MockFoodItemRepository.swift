import Foundation

/// In-memory food repository for unit tests — no network / no secrets.
final class MockFoodItemRepository: FoodItemRepositoryProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [FoodItem] = []
    private let sessionUserId: String
    private let photoRepository: MockMealPhotoRepository?

    /// If set, create/update/delete throw this error.
    var forcedError: Error?

    /// Captured for tests asserting session ownership (never overwrites with external id).
    private(set) var lastWriteSessionUserId: String?
    private(set) var lastCreatePhotoPaths: [String] = []
    private(set) var createCallCount = 0
    private(set) var updateCallCount = 0
    private(set) var lastCreateWrite: FoodItemWrite?
    private(set) var lastUpdateId: String?
    private(set) var lastUpdateWrite: FoodItemWrite?
    /// Last `fetchByDateKey` argument (stage 6 date navigation tests).
    private(set) var lastFetchDateKey: String?
    private(set) var fetchByDateKeyCallCount = 0
    private(set) var lastFetchBetween: (String, String)?
    private(set) var fetchBetweenCallCount = 0

    /// Test-only snapshot of stored items (no network).
    func itemsSnapshotForTest() -> [FoodItem] {
        withLock { items }
    }

    init(
        sessionUserId: String = "11111111-1111-1111-1111-111111111111",
        seed: [FoodItem] = [],
        photoRepository: MockMealPhotoRepository? = nil
    ) {
        self.sessionUserId = sessionUserId
        self.items = seed
        self.photoRepository = photoRepository
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
            lastFetchDateKey = dateKey
            fetchByDateKeyCallCount += 1
            return items
                .filter { $0.dateKey == dateKey }
                .sorted { $0.createdAt < $1.createdAt }
        }
    }

    func fetchBetween(startDateKey: String, endDateKey: String) async throws -> [FoodItem] {
        try throwIfForced()
        return withLock {
            lastFetchBetween = (startDateKey, endDateKey)
            fetchBetweenCallCount += 1
            return items
                .filter { $0.dateKey >= startDateKey && $0.dateKey <= endDateKey }
                .sorted { lhs, rhs in
                    if lhs.dateKey != rhs.dateKey { return lhs.dateKey < rhs.dateKey }
                    return lhs.createdAt < rhs.createdAt
                }
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
        lastCreatePhotoPaths = payload.photo_urls
        lastCreateWrite = write
        createCallCount += 1
        withLock { items.append(item) }
        return item
    }

    func update(id: String, write: FoodItemWrite) async throws -> FoodItem {
        try throwIfForced()
        lastWriteSessionUserId = sessionUserId
        lastUpdateId = id
        lastUpdateWrite = write
        updateCallCount += 1
        let payload = FoodItemMapper.insertPayload(from: write, generatedSourceId: write.sourceId)
        precondition(FoodItemMapper.assertPayloadHasNoUserId(payload))

        let previousPaths: [String] = withLock {
            items.first(where: { $0.id == id })?.photoPaths ?? []
        }
        let updated: FoodItem = try withLock {
            guard let index = items.firstIndex(where: { $0.id == id }) else {
                throw AppError.unknown(message: "记录不存在。")
            }
            let previous = items[index]
            let item = FoodItem(
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
            items[index] = item
            return item
        }

        let next = Set(write.photoPaths)
        let removed = previousPaths.filter { !next.contains($0) }
        if let photoRepository, !removed.isEmpty {
            let orphaned = removed.filter { path in
                !withLock { items.contains { $0.photoPaths.contains(path) } }
            }
            if !orphaned.isEmpty {
                try? await photoRepository.delete(paths: orphaned)
            }
        }
        return updated
    }

    func delete(id: String) async throws {
        try throwIfForced()
        lastWriteSessionUserId = sessionUserId
        let removedPaths: [String] = withLock {
            let paths = items.first(where: { $0.id == id })?.photoPaths ?? []
            items.removeAll { $0.id == id }
            return paths
        }
        if let photoRepository, !removedPaths.isEmpty {
            // Still referenced?
            let stillUsed = withLock {
                items.contains { item in
                    item.photoPaths.contains { removedPaths.contains($0) }
                }
            }
            if !stillUsed {
                try await photoRepository.delete(paths: removedPaths)
            }
        }
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
