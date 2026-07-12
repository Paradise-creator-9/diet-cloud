import Foundation

/// Test-only credential store. Still avoids UserDefaults.
final class InMemoryCredentialStore: SecureCredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data] = [:]

    /// Exposed only for tests to assert contents without printing secrets.
    var storedKeys: [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(storage.keys).sorted()
    }

    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return storage.isEmpty
    }

    func setData(_ data: Data, forKey key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        storage[key] = data
    }

    func data(forKey key: String) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    func removeData(forKey key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        storage.removeValue(forKey: key)
    }

    func removeAll(withPrefix prefix: String) throws {
        lock.lock()
        defer { lock.unlock() }
        storage = storage.filter { !$0.key.hasPrefix(prefix) }
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll()
    }
}
