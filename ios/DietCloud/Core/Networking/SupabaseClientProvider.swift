import Foundation

/// Abstraction over Supabase access. Phase 0 only validates configuration and
/// prepares the seam for supabase-swift (Auth / Database / Storage) in Phase 1+.
///
/// The app must never hold service-role, Gemini, or ingest tokens.
protocol SupabaseClientProviding: Sendable {
    var config: AppConfig { get }
    var isConfigured: Bool { get }
}

/// Phase 0 provider: no network client, no session.
/// Phase 1 will construct the real Supabase client from `config`.
final class SupabaseClientProvider: SupabaseClientProviding, @unchecked Sendable {
    let config: AppConfig

    init(config: AppConfig) {
        self.config = config
    }

    var isConfigured: Bool {
        config.isReadyForNetwork
    }

    /// Absolute URL for authenticated AI endpoints (never relative `/api/...`).
    func analyzeMealURL() -> URL {
        config.apiBaseURL.appending(path: "api/analyze-meal")
    }

    func analyzeBodyURL() -> URL {
        config.apiBaseURL.appending(path: "api/analyze-body")
    }
}
