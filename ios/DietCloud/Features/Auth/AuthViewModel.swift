import Foundation
import Observation

@MainActor
@Observable
final class AuthViewModel {
    static let defaultResendCooldownSeconds = 60

    private(set) var phase: AuthPhase = .loading
    private(set) var errorMessage: String?
    private(set) var statusMessage: String?
    private(set) var isBusy = false
    /// True only while `sendOTP` network call is in flight.
    private(set) var isSendingEmail = false
    /// Remaining seconds before another sendOTP is allowed (memory-only; resets on relaunch).
    private(set) var resendCooldownRemainingSeconds = 0

    var emailInput = ""
    var otpInput = ""

    private let repository: AuthRepositoryProtocol
    private let isConfigured: Bool
    /// When false, countdown does not auto-tick (tests advance manually).
    private let autoTickResendCooldown: Bool
    /// Stored without MainActor isolation so cancellation is safe from any context.
    nonisolated(unsafe) private var cooldownTask: Task<Void, Never>?

    /// Session restore must not hang forever (invalid Supabase URL / network).
    private let restoreTimeoutNanoseconds: UInt64 = 8_000_000_000

    /// Whether the user may start a new email send (busy + cooldown).
    var canSendEmail: Bool {
        isConfigured && !isBusy && !isSendingEmail && resendCooldownRemainingSeconds == 0
    }

    /// Primary / resend button title for email send actions.
    var sendEmailButtonTitle: String {
        if resendCooldownRemainingSeconds > 0 {
            return "重新发送（\(resendCooldownRemainingSeconds)s）"
        }
        if case .awaitingOTP = phase {
            return "重新发送邮件"
        }
        return "发送登录邮件"
    }

    init(
        repository: AuthRepositoryProtocol,
        isConfigured: Bool,
        autoTickResendCooldown: Bool = true
    ) {
        self.repository = repository
        self.isConfigured = isConfigured
        self.autoTickResendCooldown = autoTickResendCooldown
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
        guard resendCooldownRemainingSeconds == 0 else {
            errorMessage = AppError.rateLimited(retryAfterSeconds: resendCooldownRemainingSeconds).userMessage
            return
        }
        guard !isBusy, !isSendingEmail else { return }

        isBusy = true
        isSendingEmail = true
        defer {
            isBusy = false
            isSendingEmail = false
        }

        do {
            let email = try AuthRepository.normalizedEmail(emailInput)
            try await repository.sendOTP(email: email)
            phase = .awaitingOTP(email: email)
            statusMessage = "请打开邮箱中的登录链接以完成登录。如果邮件中包含验证码，也可以在下方输入。"
            otpInput = ""
            startResendCooldown(seconds: Self.defaultResendCooldownSeconds)
        } catch {
            let mapped = AuthErrorSanitizer.mapAuthFailure(error)
            errorMessage = mapped.userMessage
            if case .rateLimited = mapped {
                startResendCooldown(seconds: Self.defaultResendCooldownSeconds)
            }
            if case .awaitingOTP = phase {
                // stay on completion screen for resend failures
            } else {
                phase = .signedOut
            }
        }
    }

    /// Starts (or restarts) the resend cooldown. Memory-only; not persisted.
    func startResendCooldown(seconds: Int = AuthViewModel.defaultResendCooldownSeconds) {
        cooldownTask?.cancel()
        cooldownTask = nil
        let clamped = max(0, seconds)
        resendCooldownRemainingSeconds = clamped
        guard clamped > 0, autoTickResendCooldown else { return }

        cooldownTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                if self.resendCooldownRemainingSeconds <= 0 {
                    self.resendCooldownRemainingSeconds = 0
                    return
                }
                self.resendCooldownRemainingSeconds -= 1
                if self.resendCooldownRemainingSeconds <= 0 {
                    self.resendCooldownRemainingSeconds = 0
                    return
                }
            }
        }
    }

    /// Test hook: advance countdown without sleeping real time.
    func advanceResendCooldownForTesting(by seconds: Int) {
        guard seconds > 0 else { return }
        resendCooldownRemainingSeconds = max(0, resendCooldownRemainingSeconds - seconds)
        if resendCooldownRemainingSeconds == 0 {
            cooldownTask?.cancel()
            cooldownTask = nil
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
            cancelResendCooldown()
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
                cancelResendCooldown()
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
            cancelResendCooldown()
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
        // Keep resend cooldown so rapid re-send from email page is still blocked.
    }

    private func cancelResendCooldown() {
        cooldownTask?.cancel()
        cooldownTask = nil
        resendCooldownRemainingSeconds = 0
    }
}
