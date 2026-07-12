import Foundation
import Supabase

/// Provides the configured Supabase client (Auth / future DB / Storage).
/// The app must never hold service-role, Gemini, or ingest tokens.
protocol SupabaseClientProviding: Sendable {
    var config: AppConfig { get }
    var isConfigured: Bool { get }
    /// Real client when `isConfigured`; `nil` for placeholder / invalid config.
    var client: SupabaseClient? { get }
}

final class SupabaseClientProvider: SupabaseClientProviding, @unchecked Sendable {
    let config: AppConfig
    private let credentialStore: SecureCredentialStoring
    private let lock = NSLock()
    private var _client: SupabaseClient?
    private var clientInitFailed = false

    init(config: AppConfig, credentialStore: SecureCredentialStoring = KeychainCredentialStore()) {
        self.config = config
        self.credentialStore = credentialStore
        // Do not construct SupabaseClient in init — invalid URLs (e.g. "https:") can
        // crash or hang before any SwiftUI body runs (white screen).
    }

    var isConfigured: Bool {
        config.isReadyForNetwork && !clientInitFailed
    }

    var client: SupabaseClient? {
        lock.lock()
        defer { lock.unlock() }
        if let _client { return _client }
        guard config.isReadyForNetwork, !clientInitFailed else { return nil }
        do {
            let storage = SupabaseAuthLocalStorage(store: credentialStore)
            let created = SupabaseClient(
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
            _client = created
            return created
        } catch {
            // SupabaseClient initializer is non-throwing today; keep path defensive.
            clientInitFailed = true
            return nil
        }
    }

    func analyzeMealURL() -> URL {
        config.apiBaseURL.appending(path: "api/analyze-meal")
    }

    func analyzeBodyURL() -> URL {
        config.apiBaseURL.appending(path: "api/analyze-body")
    }
}
