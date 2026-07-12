import Foundation
import Auth

/// Bridges our secure store into supabase-swift Auth storage.
/// Ensures session JSON (including refresh token) lives in Keychain / memory — never UserDefaults.
struct SupabaseAuthLocalStorage: AuthLocalStorage, @unchecked Sendable {
    private let store: SecureCredentialStoring
    private let keyPrefix: String

    init(store: SecureCredentialStoring, keyPrefix: String = "supabase.auth.") {
        self.store = store
        self.keyPrefix = keyPrefix
    }

    func store(key: String, value: Data) throws {
        try store.setData(value, forKey: keyPrefix + key)
    }

    func retrieve(key: String) throws -> Data? {
        try store.data(forKey: keyPrefix + key)
    }

    func remove(key: String) throws {
        try store.removeData(forKey: keyPrefix + key)
    }
}
