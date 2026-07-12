import Foundation
@testable import DietCloud

/// In-memory auth double — never talks to Supabase or stores real tokens.
actor MockAuthRepository: AuthRepositoryProtocol {
    var session: AuthSessionSnapshot?
    var sendOTPCallCount = 0
    var verifyOTPCallCount = 0
    var signOutCallCount = 0
    var lastSentEmail: String?
    var lastVerifyToken: String?

    var sendOTPError: Error?
    var verifyOTPError: Error?
    var restoreError: Error?
    var signOutError: Error?

    /// When verify succeeds, this user is returned (tokens never materialize).
    var verifyResultUser = AuthUser(id: "user-1", email: "test@example.com")

    func restoreSession() async throws -> AuthSessionSnapshot? {
        if let restoreError { throw restoreError }
        if let session, session.isExpired { return nil }
        return session
    }

    func sendOTP(email: String) async throws {
        sendOTPCallCount += 1
        lastSentEmail = email
        if let sendOTPError { throw sendOTPError }
    }

    func verifyOTP(email: String, token: String) async throws -> AuthSessionSnapshot {
        verifyOTPCallCount += 1
        lastVerifyToken = token
        if let verifyOTPError { throw verifyOTPError }
        let snap = AuthSessionSnapshot(
            user: AuthUser(id: verifyResultUser.id, email: email),
            expiresAt: Date().addingTimeInterval(3600)
        )
        session = snap
        return snap
    }

    func handleAuthURL(_ url: URL) async throws -> AuthSessionSnapshot? {
        nil
    }

    func signOut() async throws {
        signOutCallCount += 1
        if let signOutError { throw signOutError }
        session = nil
    }

    func currentAccessToken() async throws -> String? {
        // Tests must never assert on real token values.
        session == nil ? nil : "test-access-token-not-a-secret"
    }
}
