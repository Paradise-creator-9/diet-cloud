import Foundation

/// Abstract secure key-value store for Auth session material.
/// Implementations must **not** use `UserDefaults`.
protocol SecureCredentialStoring: Sendable {
    func setData(_ data: Data, forKey key: String) throws
    func data(forKey key: String) throws -> Data?
    func removeData(forKey key: String) throws
    func removeAll(withPrefix prefix: String) throws
}
