import Foundation
import Security

/// Keychain-backed credential store. Tokens never go through UserDefaults.
final class KeychainCredentialStore: SecureCredentialStoring, @unchecked Sendable {
    private let service: String
    private let accessGroup: String?

    init(service: String = "app.dietcloud.DietCloud.auth", accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    func setData(_ data: Data, forKey key: String) throws {
        try removeData(forKey: key)

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AppError.auth(.keychain(status: Int(status)))
        }
    }

    func data(forKey key: String) throws -> Data? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw AppError.auth(.keychain(status: Int(status)))
        }
        return item as? Data
    }

    func removeData(forKey key: String) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppError.auth(.keychain(status: Int(status)))
        }
    }

    func removeAll(withPrefix prefix: String) throws {
        // Keychain has no prefix scan API without enumerating; delete known accounts only.
        // Callers that need wipe should pass explicit keys or use a dedicated service name.
        _ = prefix
    }
}
