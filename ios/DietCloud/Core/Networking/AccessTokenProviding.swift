import Foundation

/// Supplies the current Supabase session access token for Vercel AI calls.
/// Implementations must never log the token value.
protocol AccessTokenProviding: Sendable {
    func currentAccessToken() async throws -> String?
}

/// Fixed token for unit tests only (never a production secret).
struct FixedAccessTokenProvider: AccessTokenProviding {
    let token: String?

    func currentAccessToken() async throws -> String? {
        token
    }
}
