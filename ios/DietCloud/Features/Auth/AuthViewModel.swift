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

    /// Session restore must not hang forever (invalid Supabase URL / network).
    private let restoreTimeoutNanoseconds: UInt64 = 8_000_000_000

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
            statusMessage = "请在 Secrets.xcconfig 中填写公开的 Supabase URL 与 anon key（勿写入 service role）。"
            return
        }

        do {
            let session = try await restoreSessionWithTimeout()
            if let session, !session.isExpired {
                phase = .signedIn(session.user)
            } else {
                phase = .signedOut
                statusMessage = "输入邮箱后，会收到一封登录邮件。请打开邮件中的登录链接。"
            }
        } catch {
            phase = .signedOut
            errorMessage = AuthErrorSanitizer.mapAuthFailure(error).userMessage
            statusMessage = "无法恢复登录状态，请重新登录。"
        }
    }

    private func restoreSessionWithTimeout() async throws -> AuthSessionSnapshot? {
        let repository = self.repository
        let timeout = restoreTimeoutNanoseconds
        return try await withThrowingTaskGroup(of: AuthSessionSnapshot?.self) { group in
            group.addTask {
                try await repository.restoreSession()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeout)
                throw AppError.network(message: "登录状态恢复超时，请检查网络或配置。")
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { return nil }
            return result
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
