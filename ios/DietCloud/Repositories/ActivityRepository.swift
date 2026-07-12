import Foundation
import Supabase

protocol DailyActivityRepositoryProtocol: Sendable {
    func fetchAll() async throws -> [DailyActivity]
    func fetchByDateKey(_ dateKey: String) async throws -> [DailyActivity]
}

protocol ExerciseActivityRepositoryProtocol: Sendable {
    func fetchAll() async throws -> [ExerciseActivity]
    func fetchByDateKey(_ dateKey: String) async throws -> [ExerciseActivity]
}

final class DailyActivityRepository: DailyActivityRepositoryProtocol, @unchecked Sendable {
    private let provider: SupabaseClientProviding
    private let identity: SessionIdentityProviding

    init(provider: SupabaseClientProviding, identity: SessionIdentityProviding) {
        self.provider = provider
        self.identity = identity
    }

    func fetchAll() async throws -> [DailyActivity] {
        try await fetch(dateKey: nil)
    }

    func fetchByDateKey(_ dateKey: String) async throws -> [DailyActivity] {
        try await fetch(dateKey: dateKey)
    }

    private func fetch(dateKey: String?) async throws -> [DailyActivity] {
        guard provider.isConfigured, let client = provider.client else {
            throw AppError.auth(.notConfigured)
        }
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
}

final class ExerciseActivityRepository: ExerciseActivityRepositoryProtocol, @unchecked Sendable {
    private let provider: SupabaseClientProviding
    private let identity: SessionIdentityProviding

    init(provider: SupabaseClientProviding, identity: SessionIdentityProviding) {
        self.provider = provider
        self.identity = identity
    }

    func fetchAll() async throws -> [ExerciseActivity] {
        try await fetch(dateKey: nil)
    }

    func fetchByDateKey(_ dateKey: String) async throws -> [ExerciseActivity] {
        try await fetch(dateKey: dateKey)
    }

    private func fetch(dateKey: String?) async throws -> [ExerciseActivity] {
        guard provider.isConfigured, let client = provider.client else {
            throw AppError.auth(.notConfigured)
        }
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
}

final class MockDailyActivityRepository: DailyActivityRepositoryProtocol, @unchecked Sendable {
    var items: [DailyActivity] = []

    func fetchAll() async throws -> [DailyActivity] { items }
    func fetchByDateKey(_ dateKey: String) async throws -> [DailyActivity] {
        items.filter { $0.dateKey == dateKey }
    }
}

final class MockExerciseActivityRepository: ExerciseActivityRepositoryProtocol, @unchecked Sendable {
    var items: [ExerciseActivity] = []

    func fetchAll() async throws -> [ExerciseActivity] { items }
    func fetchByDateKey(_ dateKey: String) async throws -> [ExerciseActivity] {
        items.filter { $0.dateKey == dateKey }
    }
}
