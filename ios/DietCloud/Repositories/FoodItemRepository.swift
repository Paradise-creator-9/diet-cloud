import Foundation
import Supabase

protocol FoodItemRepositoryProtocol: Sendable {
    func fetchAll() async throws -> [FoodItem]
    func fetchByDateKey(_ dateKey: String) async throws -> [FoodItem]
    func fetchById(_ id: String) async throws -> FoodItem?
    func create(_ write: FoodItemWrite) async throws -> FoodItem
    func update(id: String, write: FoodItemWrite) async throws -> FoodItem
    func delete(id: String) async throws
    /// Local aggregation — no network.
    func nutritionSummary(for items: [FoodItem]) -> DailyNutritionSummary
}

final class FoodItemRepository: FoodItemRepositoryProtocol, @unchecked Sendable {
    private let provider: SupabaseClientProviding
    private let identity: SessionIdentityProviding
    private let photoRepository: MealPhotoRepositoryProtocol?

    init(
        provider: SupabaseClientProviding,
        identity: SessionIdentityProviding,
        photoRepository: MealPhotoRepositoryProtocol? = nil
    ) {
        self.provider = provider
        self.identity = identity
        self.photoRepository = photoRepository
    }

    private func requireClient() throws -> SupabaseClient {
        guard provider.isConfigured, let client = provider.client else {
            throw AppError.auth(.notConfigured)
        }
        return client
    }

    func fetchAll() async throws -> [FoodItem] {
        let client = try requireClient()
        _ = try await identity.requireUserId() // ensures session; RLS filters rows
        do {
            let rows: [FoodItemRow] = try await client
                .from("food_items")
                .select()
                .order("eaten_on", ascending: false)
                .order("created_at", ascending: true)
                .execute()
                .value
            return try await mapRows(rows)
        } catch {
            throw DataErrorMapping.map(error)
        }
    }

    func fetchByDateKey(_ dateKey: String) async throws -> [FoodItem] {
        let client = try requireClient()
        _ = try await identity.requireUserId()
        do {
            let rows: [FoodItemRow] = try await client
                .from("food_items")
                .select()
                .eq("eaten_on", value: dateKey)
                .order("created_at", ascending: true)
                .execute()
                .value
            return try await mapRows(rows)
        } catch {
            throw DataErrorMapping.map(error)
        }
    }

    func fetchById(_ id: String) async throws -> FoodItem? {
        let client = try requireClient()
        _ = try await identity.requireUserId()
        do {
            let rows: [FoodItemRow] = try await client
                .from("food_items")
                .select()
                .eq("id", value: id)
                .limit(1)
                .execute()
                .value
            guard let row = rows.first else { return nil }
            return try await mapRows([row]).first
        } catch {
            throw DataErrorMapping.map(error)
        }
    }

    func create(_ write: FoodItemWrite) async throws -> FoodItem {
        let client = try requireClient()
        _ = try await identity.requireUserId()
        let sourceId = write.sourceId ?? "manual-\(UUID().uuidString.lowercased())"
        let payload = FoodItemMapper.insertPayload(from: write, generatedSourceId: sourceId)
        precondition(FoodItemMapper.assertPayloadHasNoUserId(payload))
        do {
            let row: FoodItemRow = try await client
                .from("food_items")
                .insert(payload)
                .select()
                .single()
                .execute()
                .value
            return try await mapRows([row]).first!
        } catch {
            throw DataErrorMapping.map(error)
        }
    }

    func update(id: String, write: FoodItemWrite) async throws -> FoodItem {
        let client = try requireClient()
        _ = try await identity.requireUserId()
        let payload = FoodItemMapper.insertPayload(from: write, generatedSourceId: write.sourceId)
        precondition(FoodItemMapper.assertPayloadHasNoUserId(payload))
        do {
            let row: FoodItemRow = try await client
                .from("food_items")
                .update(payload)
                .eq("id", value: id)
                .select()
                .single()
                .execute()
                .value
            return try await mapRows([row]).first!
        } catch {
            throw DataErrorMapping.map(error)
        }
    }

    func delete(id: String) async throws {
        let client = try requireClient()
        let userId = try await identity.requireUserId()
        do {
            // Capture photo paths before delete (Web: deleteFoodItem + removeUnreferencedPhotoPaths).
            let existing: [FoodItemRow] = try await client
                .from("food_items")
                .select()
                .eq("id", value: id)
                .limit(1)
                .execute()
                .value
            let paths = existing.first?.photo_urls ?? []

            try await client
                .from("food_items")
                .delete()
                .eq("id", value: id)
                .execute()

            if let photoRepository, !paths.isEmpty {
                try await removeUnreferencedPhotos(userId: userId, paths: paths, photoRepository: photoRepository, client: client)
            }
        } catch {
            throw DataErrorMapping.map(error)
        }
    }

    /// Best-effort orphan cleanup — only deletes paths no longer referenced by any food_items row.
    private func removeUnreferencedPhotos(
        userId: String,
        paths: [String],
        photoRepository: MealPhotoRepositoryProtocol,
        client: SupabaseClient
    ) async throws {
        var removable: [String] = []
        for path in paths where MealPhotoPath.isOwned(path: path, byUserId: userId) {
            let refs: [FoodItemRow] = try await client
                .from("food_items")
                .select("id")
                .contains("photo_urls", value: [path])
                .limit(1)
                .execute()
                .value
            if refs.isEmpty {
                removable.append(path)
            }
        }
        if !removable.isEmpty {
            try await photoRepository.delete(paths: removable)
        }
    }

    func nutritionSummary(for items: [FoodItem]) -> DailyNutritionSummary {
        DailyNutritionSummary.totals(for: items)
    }

    private func mapRows(_ rows: [FoodItemRow]) async throws -> [FoodItem] {
        let allPaths = Array(Set(rows.flatMap { $0.photo_urls ?? [] }))
        var urlMap: [String: String] = Dictionary(uniqueKeysWithValues: allPaths.map { ($0, $0) })
        if let photoRepository, !allPaths.isEmpty {
            let signed = try await photoRepository.signedURLs(
                for: SignedURLRequest(paths: allPaths, expiresIn: SignedURLRequest.defaultTTLSeconds)
            )
            for ref in signed {
                if let url = ref.signedURL { urlMap[ref.path] = url }
            }
        }
        return try rows.map { row in
            let paths = row.photo_urls ?? []
            let urls = paths.map { urlMap[$0] ?? $0 }
            return try FoodItemMapper.domain(from: row, photoURLs: urls)
        }
    }
}
