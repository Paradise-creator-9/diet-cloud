import Foundation
import Supabase

/// Auth operations used by the feature layer. Implementations must not log tokens.
protocol AuthRepositoryProtocol: Sendable {
    /// Restore session from secure storage (Keychain via SDK storage).
    func restoreSession() async throws -> AuthSessionSnapshot?
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
            // No local session or invalid refresh → signed out (not a hard crash).
            return nil
        }
    }

    func sendOTP(email: String) async throws {
        let normalized = try Self.normalizedEmail(email)
        let client = try requireClient()
        do {
            // Same Auth API family as Web `signInWithOtp({ email })`.
            // Intentionally omit `redirectTo`: Web uses `emailRedirectTo: window.location.origin`
            // (Magic Link → browser). Passing `dietcloud://…` here would require that URL to
            // already be on the Supabase Redirect allowlist; we do not change production Auth.
            // Completion on iOS therefore depends on the live email template:
            // - if the message contains a token/code → optional `verifyOTP`
            // - if only a Magic Link → needs a reachable app redirect (not guaranteed today)
            try await client.auth.signInWithOTP(email: normalized)
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
            // Some SDK paths return user without embedding session — re-read local session.
            let session = try await client.auth.session
            return Self.snapshot(from: session)
        } catch {
            throw AuthErrorSanitizer.mapAuthFailure(error)
        }
    }

    /// Completes Magic Link **only if** the OS opens an auth callback URL into the app
    /// (e.g. `dietcloud://…` with tokens). Code is wired via `RootView.onOpenURL`, but
    /// production emails will not hit this path until Redirect URLs + `redirectTo` are set.
    func handleAuthURL(_ url: URL) async throws -> AuthSessionSnapshot? {
        let client = try requireClient()
        do {
            let session = try await client.auth.session(from: url)
            return Self.snapshot(from: session)
        } catch {
            // Not an auth callback URL — ignore quietly for app open handlers.
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
        // `expiresAt` is unix time (TimeInterval) in supabase-swift Session.
        AuthSessionSnapshot(
            user: AuthUser(id: session.user.id.uuidString, email: session.user.email),
            expiresAt: Date(timeIntervalSince1970: session.expiresAt)
        )
    }
}
