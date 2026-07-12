import Foundation
import Supabase

protocol DailyActivityRepositoryProtocol: Sendable {
    func fetchAll() async throws -> [DailyActivity]
    func fetchByDateKey(_ dateKey: String) async throws -> [DailyActivity]
    func upsert(_ write: DailyActivityWrite) async throws -> DailyActivity
    func delete(id: String) async throws
}

protocol ExerciseActivityRepositoryProtocol: Sendable {
    func fetchAll() async throws -> [ExerciseActivity]
    func fetchByDateKey(_ dateKey: String) async throws -> [ExerciseActivity]
    func create(_ write: ExerciseActivityWrite) async throws -> ExerciseActivity
    func delete(id: String) async throws
}

final class DailyActivityRepository: DailyActivityRepositoryProtocol, @unchecked Sendable {
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

    func fetchAll() async throws -> [DailyActivity] {
        try await fetch(dateKey: nil)
    }

    func fetchByDateKey(_ dateKey: String) async throws -> [DailyActivity] {
        try await fetch(dateKey: dateKey)
    }

    private func fetch(dateKey: String?) async throws -> [DailyActivity] {
        let client = try requireClient()
        _ = try await identity.requireUserId()
        do {
            var query = client.from("daily_activities").select()
            if let dateKey {
                query = query.eq("activity_on", value: dateKey)
            }
            let rows: [DailyActivityRow] = try await query
                .order("activity_on", ascending: false)
                .order("created_at", ascending: false)
                .execute()
                .value
            return try rows.map { try DailyActivityMapper.domain(from: $0) }
        } catch {
            throw DataErrorMapping.map(error)
        }
    }

    func upsert(_ write: DailyActivityWrite) async throws -> DailyActivity {
        let client = try requireClient()
        let userId = try await identity.requireUserId()
        let payload = DailyActivityMapper.upsertPayload(from: write, sessionUserId: userId)
        guard payload.user_id.lowercased() == userId.lowercased() else {
            throw AppError.unauthorized
        }
        do {
            let row: DailyActivityRow = try await client
                .from("daily_activities")
                .upsert(payload, onConflict: "user_id,activity_on,source")
                .select()
                .single()
                .execute()
                .value
            return try DailyActivityMapper.domain(from: row)
        } catch {
            throw DataErrorMapping.map(error)
        }
    }

    func delete(id: String) async throws {
        let client = try requireClient()
        _ = try await identity.requireUserId()
        do {
            try await client
                .from("daily_activities")
                .delete()
                .eq("id", value: id)
                .execute()
        } catch {
            throw DataErrorMapping.map(error)
        }
    }
}

final class ExerciseActivityRepository: ExerciseActivityRepositoryProtocol, @unchecked Sendable {
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

    func fetchAll() async throws -> [ExerciseActivity] {
        try await fetch(dateKey: nil)
    }

    func fetchByDateKey(_ dateKey: String) async throws -> [ExerciseActivity] {
        try await fetch(dateKey: dateKey)
    }

    private func fetch(dateKey: String?) async throws -> [ExerciseActivity] {
        let client = try requireClient()
        _ = try await identity.requireUserId()
        do {
            var query = client.from("exercise_activities").select()
            if let dateKey {
                query = query.eq("activity_on", value: dateKey)
            }
            let rows: [ExerciseActivityRow] = try await query
                .order("activity_on", ascending: false)
                .order("started_at", ascending: false)
                .order("created_at", ascending: false)
                .execute()
                .value
            return try rows.map { try ExerciseActivityMapper.domain(from: $0) }
        } catch {
            throw DataErrorMapping.map(error)
        }
    }

    func create(_ write: ExerciseActivityWrite) async throws -> ExerciseActivity {
        let client = try requireClient()
        let userId = try await identity.requireUserId()
        let payload = ExerciseActivityMapper.insertPayload(from: write, sessionUserId: userId)
        guard payload.user_id.lowercased() == userId.lowercased() else {
            throw AppError.unauthorized
        }
        do {
            let row: ExerciseActivityRow = try await client
                .from("exercise_activities")
                .insert(payload)
                .select()
                .single()
                .execute()
                .value
            return try ExerciseActivityMapper.domain(from: row)
        } catch {
            throw DataErrorMapping.map(error)
        }
    }

    func delete(id: String) async throws {
        let client = try requireClient()
        _ = try await identity.requireUserId()
        do {
            try await client
                .from("exercise_activities")
                .delete()
                .eq("id", value: id)
                .execute()
        } catch {
            throw DataErrorMapping.map(error)
        }
    }
}

// MARK: - Mocks

final class MockDailyActivityRepository: DailyActivityRepositoryProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [DailyActivity] = []
    private let sessionUserId: String
    private(set) var lastUpsertDateKey: String?
    private(set) var lastFetchDateKey: String?
    var forcedError: Error?

    init(
        sessionUserId: String = "11111111-1111-1111-1111-111111111111",
        seed: [DailyActivity] = []
    ) {
        self.sessionUserId = sessionUserId
        self.items = seed
    }

    func fetchAll() async throws -> [DailyActivity] {
        try throwIfForced()
        return withLock { items.sorted { $0.dateKey > $1.dateKey } }
    }

    func fetchByDateKey(_ dateKey: String) async throws -> [DailyActivity] {
        try throwIfForced()
        return withLock {
            lastFetchDateKey = dateKey
            return items.filter { $0.dateKey == dateKey }
        }
    }

    func upsert(_ write: DailyActivityWrite) async throws -> DailyActivity {
        try throwIfForced()
        let payload = DailyActivityMapper.upsertPayload(from: write, sessionUserId: sessionUserId)
        guard payload.user_id == sessionUserId else { throw AppError.unauthorized }
        let activity = DailyActivity(
            id: UUID().uuidString.lowercased(),
            dateKey: payload.activity_on,
            source: payload.source,
            steps: payload.steps,
            activeCalories: payload.active_calories,
            totalCalories: payload.total_calories,
            exerciseMinutes: payload.exercise_minutes,
            standHours: payload.stand_hours,
            distanceKm: payload.distance_km,
            floors: payload.floors,
            restingHeartRate: payload.resting_heart_rate,
            hrvMs: payload.hrv_ms,
            sleepMinutes: payload.sleep_minutes,
            rawMetrics: [:],
            note: payload.note ?? "",
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        withLock {
            lastUpsertDateKey = activity.dateKey
            items.removeAll { $0.dateKey == activity.dateKey && $0.source == activity.source }
            items.append(activity)
        }
        return activity
    }

    func delete(id: String) async throws {
        try throwIfForced()
        withLock { items.removeAll { $0.id == id } }
    }

    private func throwIfForced() throws {
        if let forcedError { throw forcedError }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }
}

final class MockExerciseActivityRepository: ExerciseActivityRepositoryProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [ExerciseActivity] = []
    private let sessionUserId: String
    private(set) var lastCreateDateKey: String?
    private(set) var lastFetchDateKey: String?
    var forcedError: Error?

    init(
        sessionUserId: String = "11111111-1111-1111-1111-111111111111",
        seed: [ExerciseActivity] = []
    ) {
        self.sessionUserId = sessionUserId
        self.items = seed
    }

    func fetchAll() async throws -> [ExerciseActivity] {
        try throwIfForced()
        return withLock { items }
    }

    func fetchByDateKey(_ dateKey: String) async throws -> [ExerciseActivity] {
        try throwIfForced()
        return withLock {
            lastFetchDateKey = dateKey
            return items.filter { $0.dateKey == dateKey }
        }
    }

    func create(_ write: ExerciseActivityWrite) async throws -> ExerciseActivity {
        try throwIfForced()
        let payload = ExerciseActivityMapper.insertPayload(from: write, sessionUserId: sessionUserId)
        guard payload.user_id == sessionUserId else { throw AppError.unauthorized }
        let exercise = ExerciseActivity(
            id: UUID().uuidString.lowercased(),
            dateKey: payload.activity_on,
            startedAt: payload.started_at ?? "",
            source: payload.source,
            externalId: payload.external_id ?? "",
            type: payload.type,
            title: payload.title,
            durationMinutes: payload.duration_minutes,
            distanceKm: payload.distance_km,
            activeCalories: payload.active_calories,
            avgHeartRate: payload.avg_heart_rate,
            maxHeartRate: payload.max_heart_rate,
            elevationGainM: payload.elevation_gain_m,
            note: payload.note ?? "",
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        withLock {
            lastCreateDateKey = exercise.dateKey
            items.append(exercise)
        }
        return exercise
    }

    func delete(id: String) async throws {
        try throwIfForced()
        withLock { items.removeAll { $0.id == id } }
    }

    private func throwIfForced() throws {
        if let forcedError { throw forcedError }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }
}
