import Foundation
import Observation

@MainActor
@Observable
final class AuthViewModel {
    private(set) var phase: AuthPhase = .loading
    private(set) var errorMessage: String?
    private(set) var statusMessage: String?
    private(set) var isBusy = false

    var emailInput = ""
    var otpInput = ""

    private let repository: AuthRepositoryProtocol
    private let isConfigured: Bool

    init(repository: AuthRepositoryProtocol, isConfigured: Bool) {
        self.repository = repository
        self.isConfigured = isConfigured
    }

    /// Cold start: restore session from Keychain-backed Supabase storage.
    func bootstrap() async {
        phase = .loading
        errorMessage = nil
        statusMessage = nil

        guard isConfigured else {
            phase = .signedOut
            errorMessage = AppError.auth(.notConfigured).userMessage
            return
        }

        do {
            if let session = try await repository.restoreSession(), !session.isExpired {
                phase = .signedIn(session.user)
            } else {
                phase = .signedOut
                statusMessage = "输入邮箱后，会收到一封登录邮件。请打开邮件中的登录链接。"
            }
        } catch {
            phase = .signedOut
            errorMessage = AuthErrorSanitizer.mapAuthFailure(error).userMessage
        }
    }

    func sendOTP() async {
        errorMessage = nil
        guard isConfigured else {
            errorMessage = AppError.auth(.notConfigured).userMessage
            return
        }

        isBusy = true
        defer { isBusy = false }

        do {
            let email = try AuthRepository.normalizedEmail(emailInput)
            try await repository.sendOTP(email: email)
            phase = .awaitingOTP(email: email)
            statusMessage = "请打开邮箱中的登录链接以完成登录。如果邮件中包含验证码，也可以在下方输入。"
            otpInput = ""
        } catch {
            let mapped = AuthErrorSanitizer.mapAuthFailure(error)
            errorMessage = mapped.userMessage
            if case .awaitingOTP = phase {
                // stay on completion screen for resend failures
            } else {
                phase = .signedOut
            }
        }
    }

    func verifyOTP() async {
        errorMessage = nil
        guard case .awaitingOTP(let email) = phase else { return }

        isBusy = true
        defer { isBusy = false }

        do {
            let session = try await repository.verifyOTP(email: email, token: otpInput)
            phase = .signedIn(session.user)
            statusMessage = nil
            otpInput = ""
        } catch {
            errorMessage = AuthErrorSanitizer.mapAuthFailure(error).userMessage
        }
    }

    func handleOpenURL(_ url: URL) async {
        guard isConfigured else { return }
        do {
            if let session = try await repository.handleAuthURL(url) {
                phase = .signedIn(session.user)
                errorMessage = nil
                statusMessage = nil
            }
        } catch {
            let mapped = AuthErrorSanitizer.mapAuthFailure(error)
            errorMessage = mapped.userMessage
            // Stay on current phase (often awaitingOTP) so user can retry or use code.
            if case .loading = phase {
                phase = .signedOut
            }
        }
    }

    func signOut() async {
        errorMessage = nil
        isBusy = true
        defer { isBusy = false }

        do {
            if isConfigured {
                try await repository.signOut()
            }
            phase = .signedOut
            statusMessage = "已退出登录。"
            otpInput = ""
        } catch {
            phase = .signedOut
            errorMessage = AuthErrorSanitizer.mapAuthFailure(error).userMessage
        }
    }

    func backToEmailEntry() {
        phase = .signedOut
        otpInput = ""
        errorMessage = nil
        statusMessage = "输入邮箱后，会收到一封登录邮件。请打开邮件中的登录链接。"
    }
}
