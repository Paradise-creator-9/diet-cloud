import Foundation

/// Authenticated user surface for UI — never includes tokens.
struct AuthUser: Equatable, Sendable {
    let id: String
    let email: String?

    /// e.g. `a***@example.com` — safe for UI.
    var redactedEmail: String {
        guard let email, let at = email.firstIndex(of: "@") else {
            return "已登录"
        }
        let local = email[..<at]
        let domain = email[email.index(after: at)...]
        let first = local.prefix(1)
        return "\(first)***@\(domain)"
    }
}

/// High-level auth routing state for the app shell.
enum AuthPhase: Equatable, Sendable {
    case loading
    case signedOut
    case awaitingOTP(email: String)
    case signedIn(AuthUser)
}

/// Lightweight session snapshot used by the repository layer.
/// Access/refresh tokens stay inside the secure store / SDK — not here.
struct AuthSessionSnapshot: Equatable, Sendable {
    let user: AuthUser
    let expiresAt: Date?

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date()
    }
}
