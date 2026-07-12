import Foundation
import Supabase

protocol BodyMetricsRepositoryProtocol: Sendable {
    func fetchAll() async throws -> [BodyMetric]
    func fetchByDateKey(_ dateKey: String) async throws -> BodyMetric?
    func upsert(_ write: BodyMetricWrite) async throws -> BodyMetric
    func delete(id: String) async throws
}

final class BodyMetricsRepository: BodyMetricsRepositoryProtocol, @unchecked Sendable {
    private let provider: SupabaseClientProviding
    private let identity: SessionIdentityProviding

    init(provider: SupabaseClientProviding, identity: SessionIdentityProviding) {
        self.provider = provider
        self.identity = identity
    }

    private func requireClient() throws -> SupabaseClient {
        guard provider.isConfigured, let client = provider.client else {
            throw AppError.auth(.notConfigured)
        }
        return client
    }

    func fetchAll() async throws -> [BodyMetric] {
        let client = try requireClient()
        _ = try await identity.requireUserId()
        do {
            let rows: [BodyMetricRow] = try await client
                .from("body_metrics")
                .select()
                .order("measured_on", ascending: false)
                .order("created_at", ascending: false)
                .execute()
                .value
            return try rows.map { try BodyMetricMapper.domain(from: $0) }
        } catch {
            throw DataErrorMapping.map(error)
        }
    }

    func fetchByDateKey(_ dateKey: String) async throws -> BodyMetric? {
        let client = try requireClient()
        _ = try await identity.requireUserId()
        do {
            let rows: [BodyMetricRow] = try await client
                .from("body_metrics")
                .select()
                .eq("measured_on", value: dateKey)
                .limit(1)
                .execute()
                .value
            guard let row = rows.first else { return nil }
            return try BodyMetricMapper.domain(from: row)
        } catch {
            throw DataErrorMapping.map(error)
        }
    }

    func upsert(_ write: BodyMetricWrite) async throws -> BodyMetric {
        let client = try requireClient()
        let userId = try await identity.requireUserId()
        let payload = BodyMetricMapper.upsertPayload(from: write, sessionUserId: userId)
        // Guard: payload user_id must equal session — never an external override.
        guard payload.user_id.lowercased() == userId.lowercased() else {
            throw AppError.unauthorized
        }
        do {
            let row: BodyMetricRow = try await client
                .from("body_metrics")
                .upsert(payload, onConflict: "user_id,measured_on")
                .select()
                .single()
                .execute()
                .value
            return try BodyMetricMapper.domain(from: row)
        } catch {
            throw DataErrorMapping.map(error)
        }
    }

    func delete(id: String) async throws {
        let client = try requireClient()
        _ = try await identity.requireUserId()
        do {
            try await client
                .from("body_metrics")
                .delete()
                .eq("id", value: id)
                .execute()
        } catch {
            throw DataErrorMapping.map(error)
        }
    }
}

final class MockBodyMetricsRepository: BodyMetricsRepositoryProtocol, @unchecked Sendable {
    private var items: [BodyMetric] = []
    private let sessionUserId: String
    private(set) var lastUpsertUserId: String?

    init(sessionUserId: String = "11111111-1111-1111-1111-111111111111") {
        self.sessionUserId = sessionUserId
    }

    func fetchAll() async throws -> [BodyMetric] {
        items.sorted { $0.dateKey > $1.dateKey }
    }

    func fetchByDateKey(_ dateKey: String) async throws -> BodyMetric? {
        items.first { $0.dateKey == dateKey }
    }

    func upsert(_ write: BodyMetricWrite) async throws -> BodyMetric {
        let payload = BodyMetricMapper.upsertPayload(from: write, sessionUserId: sessionUserId)
        lastUpsertUserId = payload.user_id
        guard payload.user_id == sessionUserId else { throw AppError.unauthorized }
        let metric = try BodyMetricMapper.domain(from: BodyMetricRow(
            id: UUID().uuidString.lowercased(),
            user_id: payload.user_id,
            measured_on: payload.measured_on,
            measured_at: payload.measured_at,
            score: payload.score,
            weight_kg: payload.weight_kg,
            bmi: payload.bmi,
            body_fat_percent: payload.body_fat_percent,
            body_age: payload.body_age,
            body_type: payload.body_type,
            muscle_kg: payload.muscle_kg,
            skeletal_muscle_kg: payload.skeletal_muscle_kg,
            bone_mass_kg: payload.bone_mass_kg,
            water_percent: payload.water_percent,
            visceral_fat: payload.visceral_fat,
            bmr_kcal: payload.bmr_kcal,
            protein_percent: payload.protein_percent,
            trunk_fat_percent: payload.trunk_fat_percent,
            trunk_muscle_kg: payload.trunk_muscle_kg,
            left_arm_fat_percent: payload.left_arm_fat_percent,
            left_arm_muscle_kg: payload.left_arm_muscle_kg,
            right_arm_fat_percent: payload.right_arm_fat_percent,
            right_arm_muscle_kg: payload.right_arm_muscle_kg,
            left_leg_fat_percent: payload.left_leg_fat_percent,
            left_leg_muscle_kg: payload.left_leg_muscle_kg,
            right_leg_fat_percent: payload.right_leg_fat_percent,
            right_leg_muscle_kg: payload.right_leg_muscle_kg,
            note: payload.note,
            created_at: ISO8601DateFormatter().string(from: Date())
        ))
        items.removeAll { $0.dateKey == metric.dateKey }
        items.append(metric)
        return metric
    }

    func delete(id: String) async throws {
        items.removeAll { $0.id == id }
    }
}
