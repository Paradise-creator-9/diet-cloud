import Foundation
import Supabase

/// Parameters used when requesting an email login message (no tokens).
struct AuthSendOTPParameters: Equatable, Sendable {
    let email: String
    let redirectTo: URL
}

/// Auth operations used by the feature layer. Implementations must not log tokens.
protocol AuthRepositoryProtocol: Sendable {
    /// Restore session from secure storage (Keychain via SDK storage).
    func restoreSession() async throws -> AuthSessionSnapshot?
    /// Builds send parameters (email + redirect). Exposed for unit tests without network.
    func makeSendOTPParameters(email: String) async throws -> AuthSendOTPParameters
    func sendOTP(email: String) async throws
    func verifyOTP(email: String, token: String) async throws -> AuthSessionSnapshot
    /// Magic-link / deep-link completion when Supabase redirects into the app.
    func handleAuthURL(_ url: URL) async throws -> AuthSessionSnapshot?
    func signOut() async throws
    func currentAccessToken() async throws -> String?
}

final class AuthRepository: AuthRepositoryProtocol, @unchecked Sendable {
    private let provider: SupabaseClientProviding

    init(provider: SupabaseClientProviding) {
        self.provider = provider
    }

    private func requireClient() throws -> SupabaseClient {
        guard provider.isConfigured, let client = provider.client else {
            throw AppError.auth(.notConfigured)
        }
        return client
    }

    func restoreSession() async throws -> AuthSessionSnapshot? {
        let client = try requireClient()
        do {
            let session = try await client.auth.session
            if session.isExpired {
                _ = try await client.auth.refreshSession()
                let refreshed = try await client.auth.session
                return Self.snapshot(from: refreshed)
            }
            return Self.snapshot(from: session)
        } catch {
            return nil
        }
    }

    func makeSendOTPParameters(email: String) async throws -> AuthSendOTPParameters {
        let normalized = try Self.normalizedEmail(email)
        // Always use configured Magic Link redirect (default dietcloud://auth-callback).
        let redirect = provider.config.authRedirectURL
        return AuthSendOTPParameters(email: normalized, redirectTo: redirect)
    }

    func sendOTP(email: String) async throws {
        let params = try await makeSendOTPParameters(email: email)
        let client = try requireClient()
        do {
            // Web: signInWithOtp + emailRedirectTo: origin (browser Magic Link).
            // iOS: same API family with redirectTo → dietcloud://auth-callback (app Magic Link).
            // Requires Supabase Dashboard Redirect URLs to include this value (manual; not in repo).
            try await client.auth.signInWithOTP(
                email: params.email,
                redirectTo: params.redirectTo
            )
        } catch {
            throw AuthErrorSanitizer.mapAuthFailure(error)
        }
    }

    func verifyOTP(email: String, token: String) async throws -> AuthSessionSnapshot {
        let normalized = try Self.normalizedEmail(email)
        let code = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { throw AppError.auth(.invalidOTP) }

        let client = try requireClient()
        do {
            let response = try await client.auth.verifyOTP(
                email: normalized,
                token: code,
                type: .email
            )
            if let session = response.session {
                return Self.snapshot(from: session)
            }
            let session = try await client.auth.session
            return Self.snapshot(from: session)
        } catch {
            throw AuthErrorSanitizer.mapAuthFailure(error)
        }
    }

    /// Completes Magic Link when OS opens the auth callback URL into the app.
    func handleAuthURL(_ url: URL) async throws -> AuthSessionSnapshot? {
        let client = try requireClient()
        do {
            let session = try await client.auth.session(from: url)
            return Self.snapshot(from: session)
        } catch {
            if url.scheme?.hasPrefix("dietcloud") != true {
                return nil
            }
            throw AuthErrorSanitizer.mapAuthFailure(error)
        }
    }

    func signOut() async throws {
        let client = try requireClient()
        do {
            try await client.auth.signOut()
        } catch {
            throw AuthErrorSanitizer.mapAuthFailure(error)
        }
    }

    func currentAccessToken() async throws -> String? {
        let client = try requireClient()
        do {
            let session = try await client.auth.session
            return session.accessToken
        } catch {
            return nil
        }
    }

    static func normalizedEmail(_ email: String) throws -> String {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.contains("@"), trimmed.contains("."), trimmed.count >= 5 else {
            throw AppError.auth(.invalidEmail)
        }
        return trimmed
    }

    static func snapshot(from session: Session) -> AuthSessionSnapshot {
        AuthSessionSnapshot(
            user: AuthUser(id: session.user.id.uuidString, email: session.user.email),
            expiresAt: Date(timeIntervalSince1970: session.expiresAt)
        )
    }
}
