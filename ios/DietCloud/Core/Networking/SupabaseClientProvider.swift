import Foundation
import Supabase

/// Provides the configured Supabase client (Auth / future DB / Storage).
/// The app must never hold service-role, Gemini, or ingest tokens.
protocol SupabaseClientProviding: Sendable {
    var config: AppConfig { get }
    var isConfigured: Bool { get }
    /// Real client when `isConfigured`; `nil` for placeholder config.
    var client: SupabaseClient? { get }
}

final class SupabaseClientProvider: SupabaseClientProviding, @unchecked Sendable {
    let config: AppConfig
    let client: SupabaseClient?
    private let credentialStore: SecureCredentialStoring

    init(config: AppConfig, credentialStore: SecureCredentialStoring = KeychainCredentialStore()) {
        self.config = config
        self.credentialStore = credentialStore

        if config.isReadyForNetwork {
            let storage = SupabaseAuthLocalStorage(store: credentialStore)
            self.client = SupabaseClient(
                supabaseURL: config.supabaseURL,
                supabaseKey: config.supabaseAnonKey,
                options: SupabaseClientOptions(
                    auth: SupabaseClientOptions.AuthOptions(
                        storage: storage,
                        autoRefreshToken: true,
                        emitLocalSessionAsInitialSession: true
                    )
                )
            )
        } else {
            self.client = nil
        }
    }

    var isConfigured: Bool {
        config.isReadyForNetwork && client != nil
    }

    func analyzeMealURL() -> URL {
        config.apiBaseURL.appending(path: "api/analyze-meal")
    }

    func analyzeBodyURL() -> URL {
        config.apiBaseURL.appending(path: "api/analyze-body")
    }
}
