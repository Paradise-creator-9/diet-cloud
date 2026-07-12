import Foundation
@testable import DietCloud

/// In-memory auth double — never talks to Supabase or stores real tokens.
final class MockAuthRepository: AuthRepositoryProtocol, @unchecked Sendable {
    private let lock = NSLock()

    private var _session: AuthSessionSnapshot?
    private var _sendOTPCallCount = 0
    private var _verifyOTPCallCount = 0
    private var _signOutCallCount = 0
    private var _handleAuthURLCallCount = 0
    private var _lastSentEmail: String?
    private var _lastVerifyToken: String?
    private var _lastRedirectTo: URL?
    private var _lastOpenURL: URL?

    private var _sendOTPError: Error?
    private var _verifyOTPError: Error?
    private var _restoreError: Error?
    private var _signOutError: Error?
    private var _handleAuthURLError: Error?
    private var _handleAuthURLResult: AuthSessionSnapshot?
    private var _configuredRedirectURL = AppConfig.defaultAuthRedirectURL
    private var _verifyResultUser = AuthUser(id: "user-1", email: "test@example.com")

    var sendOTPCallCount: Int { withLock { _sendOTPCallCount } }
    var verifyOTPCallCount: Int { withLock { _verifyOTPCallCount } }
    var signOutCallCount: Int { withLock { _signOutCallCount } }
    var handleAuthURLCallCount: Int { withLock { _handleAuthURLCallCount } }
    var lastSentEmail: String? { withLock { _lastSentEmail } }
    var lastVerifyToken: String? { withLock { _lastVerifyToken } }
    var lastRedirectTo: URL? { withLock { _lastRedirectTo } }
    var lastOpenURL: URL? { withLock { _lastOpenURL } }
    var session: AuthSessionSnapshot? { withLock { _session } }

    func setSession(_ value: AuthSessionSnapshot?) {
        withLock { _session = value }
    }

    func setVerifyError(_ error: Error?) {
        withLock { _verifyOTPError = error }
    }

    func setConfiguredRedirect(_ url: URL) {
        withLock { _configuredRedirectURL = url }
    }

    func setHandleAuthResult(_ value: AuthSessionSnapshot?) {
        withLock { _handleAuthURLResult = value }
    }

    func setHandleAuthError(_ error: Error?) {
        withLock { _handleAuthURLError = error }
    }

    func restoreSession() async throws -> AuthSessionSnapshot? {
        if let restoreError = withLock({ _restoreError }) { throw restoreError }
        let session = withLock { _session }
        if let session, session.isExpired { return nil }
        return session
    }

    func makeSendOTPParameters(email: String) async throws -> AuthSendOTPParameters {
        let normalized = try AuthRepository.normalizedEmail(email)
        let redirect = withLock { _configuredRedirectURL }
        return AuthSendOTPParameters(email: normalized, redirectTo: redirect)
    }

    func sendOTP(email: String) async throws {
        let params = try await makeSendOTPParameters(email: email)
        withLock {
            _sendOTPCallCount += 1
            _lastSentEmail = params.email
            _lastRedirectTo = params.redirectTo
        }
        if let sendOTPError = withLock({ _sendOTPError }) { throw sendOTPError }
    }

    func verifyOTP(email: String, token: String) async throws -> AuthSessionSnapshot {
        withLock {
            _verifyOTPCallCount += 1
            _lastVerifyToken = token
        }
        if let verifyOTPError = withLock({ _verifyOTPError }) { throw verifyOTPError }
        let userId = withLock { _verifyResultUser.id }
        let snap = AuthSessionSnapshot(
            user: AuthUser(id: userId, email: email),
            expiresAt: Date().addingTimeInterval(3600)
        )
        withLock { _session = snap }
        return snap
    }

    func handleAuthURL(_ url: URL) async throws -> AuthSessionSnapshot? {
        withLock {
            _handleAuthURLCallCount += 1
            _lastOpenURL = url
        }
        if let handleAuthURLError = withLock({ _handleAuthURLError }) { throw handleAuthURLError }
        if let result = withLock({ _handleAuthURLResult }) {
            withLock { _session = result }
            return result
        }
        return nil
    }

    func signOut() async throws {
        withLock { _signOutCallCount += 1 }
        if let signOutError = withLock({ _signOutError }) { throw signOutError }
        withLock { _session = nil }
    }

    func currentAccessToken() async throws -> String? {
        withLock { _session == nil ? nil : "test-access-token-not-a-secret" }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
