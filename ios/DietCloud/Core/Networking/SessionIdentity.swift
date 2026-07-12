import Foundation
import Supabase

/// Resolves the authenticated user id. Never accept arbitrary external userIds for RLS writes.
protocol SessionIdentityProviding: Sendable {
    func requireUserId() async throws -> String
}

struct SupabaseSessionIdentity: SessionIdentityProviding {
    private let provider: SupabaseClientProviding

    init(provider: SupabaseClientProviding) {
        self.provider = provider
    }

    func requireUserId() async throws -> String {
        guard provider.isConfigured, let client = provider.client else {
            throw AppError.auth(.notConfigured)
        }
        do {
            let session = try await client.auth.session
            return session.user.id.uuidString.lowercased()
        } catch {
            throw AuthErrorSanitizer.mapAuthFailure(error)
        }
    }
}

/// Test double with a fixed user id.
struct FixedSessionIdentity: SessionIdentityProviding {
    let userId: String

    func requireUserId() async throws -> String {
        userId
    }
}
