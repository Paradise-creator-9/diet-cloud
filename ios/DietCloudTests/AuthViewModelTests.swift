import XCTest
@testable import DietCloud

@MainActor
final class AuthViewModelTests: XCTestCase {
    func testBootstrapWithoutSessionIsSignedOut() async {
        let repo = MockAuthRepository()
        let vm = AuthViewModel(repository: repo, isConfigured: true)
        await vm.bootstrap()
        XCTAssertEqual(vm.phase, .signedOut)
    }

    func testBootstrapWithValidSessionIsSignedIn() async {
        let repo = MockAuthRepository()
        let user = AuthUser(id: "abc", email: "user@example.com")
        repo.setSession(
            AuthSessionSnapshot(user: user, expiresAt: Date().addingTimeInterval(3600))
        )
        let vm = AuthViewModel(repository: repo, isConfigured: true)
        await vm.bootstrap()
        XCTAssertEqual(vm.phase, .signedIn(user))
    }

    func testBootstrapWhenNotConfiguredShowsSafeError() async {
        let repo = MockAuthRepository()
        let vm = AuthViewModel(repository: repo, isConfigured: false)
        await vm.bootstrap()
        XCTAssertEqual(vm.phase, .signedOut)
        XCTAssertEqual(vm.errorMessage, AppError.auth(.notConfigured).userMessage)
        XCTAssertFalse((vm.errorMessage ?? "").contains("eyJ"))
    }

    func testSendOTPSuccessMovesToAwaitingOTPAndUsesRedirect() async {
        let repo = MockAuthRepository()
        let customRedirect = URL(string: "dietcloud://auth-callback")!
        repo.setConfiguredRedirect(customRedirect)
        let vm = AuthViewModel(repository: repo, isConfigured: true)
        vm.emailInput = "User@Example.com"
        await vm.sendOTP()
        XCTAssertEqual(vm.phase, .awaitingOTP(email: "user@example.com"))
        XCTAssertEqual(repo.sendOTPCallCount, 1)
        XCTAssertEqual(repo.lastRedirectTo, customRedirect)
        XCTAssertTrue(vm.statusMessage?.contains("登录链接") == true)
    }

    func testVerifyOTPSuccessSignsIn() async {
        let repo = MockAuthRepository()
        let vm = AuthViewModel(repository: repo, isConfigured: true)
        vm.emailInput = "user@example.com"
        await vm.sendOTP()
        vm.otpInput = "123456"
        await vm.verifyOTP()
        if case .signedIn(let user) = vm.phase {
            XCTAssertEqual(user.email, "user@example.com")
        } else {
            XCTFail("Expected signedIn, got \(vm.phase)")
        }
    }

    func testVerifyOTPFailureSetsErrorAndStaysAwaiting() async {
        let repo = MockAuthRepository()
        repo.setVerifyError(AppError.auth(.invalidOTP))
        let vm = AuthViewModel(repository: repo, isConfigured: true)
        vm.emailInput = "user@example.com"
        await vm.sendOTP()
        vm.otpInput = "000000"
        await vm.verifyOTP()
        XCTAssertEqual(vm.phase, .awaitingOTP(email: "user@example.com"))
        XCTAssertEqual(vm.errorMessage, AppError.auth(.invalidOTP).userMessage)
    }

    func testHandleOpenURLSuccessSignsIn() async {
        let repo = MockAuthRepository()
        let user = AuthUser(id: "from-link", email: "link@example.com")
        repo.setHandleAuthResult(
            AuthSessionSnapshot(user: user, expiresAt: Date().addingTimeInterval(3600))
        )
        let vm = AuthViewModel(repository: repo, isConfigured: true)
        vm.emailInput = "link@example.com"
        await vm.sendOTP()
        XCTAssertEqual(vm.phase, .awaitingOTP(email: "link@example.com"))

        await vm.handleOpenURL(URL(string: "dietcloud://auth-callback")!)
        XCTAssertEqual(vm.phase, .signedIn(user))
        XCTAssertNil(vm.errorMessage)
        XCTAssertEqual(repo.handleAuthURLCallCount, 1)
    }

    func testHandleOpenURLFailureSetsSafeErrorWithoutTokenLeak() async {
        let repo = MockAuthRepository()
        let jwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.payload.signature"
        repo.setHandleAuthError(AppError.auth(.provider(message: "bad session \(jwt)")))
        let vm = AuthViewModel(repository: repo, isConfigured: true)
        vm.emailInput = "user@example.com"
        await vm.sendOTP()

        await vm.handleOpenURL(URL(string: "dietcloud://auth-callback")!)
        XCTAssertEqual(vm.phase, .awaitingOTP(email: "user@example.com"))
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertFalse(vm.errorMessage!.contains("eyJ"))
        XCTAssertFalse(vm.errorMessage!.contains(jwt))
    }

    func testSignOutReturnsToSignedOut() async {
        let repo = MockAuthRepository()
        let user = AuthUser(id: "abc", email: "user@example.com")
        repo.setSession(
            AuthSessionSnapshot(user: user, expiresAt: Date().addingTimeInterval(3600))
        )
        let vm = AuthViewModel(repository: repo, isConfigured: true)
        await vm.bootstrap()
        await vm.signOut()
        XCTAssertEqual(vm.phase, .signedOut)
        XCTAssertEqual(repo.signOutCallCount, 1)
        XCTAssertNil(repo.session)
    }

    func testInvalidEmailDoesNotCallRepository() async {
        let repo = MockAuthRepository()
        let vm = AuthViewModel(repository: repo, isConfigured: true)
        vm.emailInput = "not-an-email"
        await vm.sendOTP()
        XCTAssertEqual(vm.phase, .signedOut)
        XCTAssertEqual(vm.errorMessage, AppError.auth(.invalidEmail).userMessage)
        XCTAssertEqual(repo.sendOTPCallCount, 0)
    }

    // MARK: - Resend cooldown

    func testInitialStateCanSendEmail() {
        let repo = MockAuthRepository()
        let vm = AuthViewModel(repository: repo, isConfigured: true, autoTickResendCooldown: false)
        XCTAssertTrue(vm.canSendEmail)
        XCTAssertEqual(vm.resendCooldownRemainingSeconds, 0)
        XCTAssertEqual(vm.sendEmailButtonTitle, "发送登录邮件")
    }

    func testSendOTPSuccessStartsSixtySecondCooldown() async {
        let repo = MockAuthRepository()
        let vm = AuthViewModel(repository: repo, isConfigured: true, autoTickResendCooldown: false)
        vm.emailInput = "user@example.com"
        await vm.sendOTP()
        XCTAssertEqual(vm.phase, .awaitingOTP(email: "user@example.com"))
        XCTAssertEqual(vm.resendCooldownRemainingSeconds, AuthViewModel.defaultResendCooldownSeconds)
        XCTAssertFalse(vm.canSendEmail)
        XCTAssertTrue(vm.sendEmailButtonTitle.contains("60s") || vm.sendEmailButtonTitle.contains("\(AuthViewModel.defaultResendCooldownSeconds)s"))
    }

    func testCooldownBlocksSecondSendWithoutWaitingRealTime() async {
        let repo = MockAuthRepository()
        let vm = AuthViewModel(repository: repo, isConfigured: true, autoTickResendCooldown: false)
        vm.emailInput = "user@example.com"
        await vm.sendOTP()
        XCTAssertEqual(repo.sendOTPCallCount, 1)

        await vm.sendOTP()
        XCTAssertEqual(repo.sendOTPCallCount, 1, "second send must be blocked during cooldown")
        XCTAssertEqual(vm.errorMessage, AppError.rateLimited(retryAfterSeconds: nil).userMessage)
        XCTAssertFalse((vm.errorMessage ?? "").contains("eyJ"))
    }

    func testCooldownEndRestoresCanSend() async {
        let repo = MockAuthRepository()
        let vm = AuthViewModel(repository: repo, isConfigured: true, autoTickResendCooldown: false)
        vm.emailInput = "user@example.com"
        await vm.sendOTP()
        XCTAssertFalse(vm.canSendEmail)

        vm.advanceResendCooldownForTesting(by: AuthViewModel.defaultResendCooldownSeconds)
        XCTAssertEqual(vm.resendCooldownRemainingSeconds, 0)
        XCTAssertTrue(vm.canSendEmail)
        XCTAssertEqual(vm.sendEmailButtonTitle, "重新发送邮件")

        await vm.sendOTP()
        XCTAssertEqual(repo.sendOTPCallCount, 2)
        XCTAssertEqual(vm.resendCooldownRemainingSeconds, AuthViewModel.defaultResendCooldownSeconds)
    }

    func testRateLimitErrorEntersCooldownWithSafeMessage() async {
        let repo = MockAuthRepository()
        repo.setSendOTPError(AppError.rateLimited(retryAfterSeconds: 60))
        let vm = AuthViewModel(repository: repo, isConfigured: true, autoTickResendCooldown: false)
        vm.emailInput = "user@example.com"
        await vm.sendOTP()

        XCTAssertEqual(vm.phase, .signedOut)
        XCTAssertEqual(vm.errorMessage, "请求过于频繁，请稍后再试。")
        XCTAssertEqual(vm.resendCooldownRemainingSeconds, AuthViewModel.defaultResendCooldownSeconds)
        XCTAssertFalse(vm.canSendEmail)
        XCTAssertFalse((vm.errorMessage ?? "").contains("eyJ"))
        XCTAssertEqual(repo.sendOTPCallCount, 1)

        // Still blocked until cooldown advances
        await vm.sendOTP()
        XCTAssertEqual(repo.sendOTPCallCount, 1)
    }

    func testRateLimitProviderMessageMapsSafelyAndCooldowns() async {
        let repo = MockAuthRepository()
        let jwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.payload.signature"
        repo.setSendOTPError(
            NSError(
                domain: "Auth",
                code: 429,
                userInfo: [NSLocalizedDescriptionKey: "For security purposes, you can only request this after 60 seconds. \(jwt)"]
            )
        )
        let vm = AuthViewModel(repository: repo, isConfigured: true, autoTickResendCooldown: false)
        vm.emailInput = "user@example.com"
        await vm.sendOTP()

        XCTAssertEqual(vm.errorMessage, AppError.rateLimited(retryAfterSeconds: nil).userMessage)
        XCTAssertFalse(vm.errorMessage!.contains("eyJ"))
        XCTAssertFalse(vm.errorMessage!.contains(jwt))
        XCTAssertEqual(vm.resendCooldownRemainingSeconds, AuthViewModel.defaultResendCooldownSeconds)
        XCTAssertFalse(vm.canSendEmail)
    }

    func testNetworkErrorDoesNotEnterCooldown() async {
        let repo = MockAuthRepository()
        repo.setSendOTPError(AppError.network(message: "network down"))
        let vm = AuthViewModel(repository: repo, isConfigured: true, autoTickResendCooldown: false)
        vm.emailInput = "user@example.com"
        await vm.sendOTP()

        XCTAssertEqual(vm.resendCooldownRemainingSeconds, 0)
        XCTAssertTrue(vm.canSendEmail)
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertFalse((vm.errorMessage ?? "").contains("eyJ"))
    }

    func testNotConfiguredDoesNotEnterCooldown() async {
        let repo = MockAuthRepository()
        let vm = AuthViewModel(repository: repo, isConfigured: false, autoTickResendCooldown: false)
        vm.emailInput = "user@example.com"
        await vm.sendOTP()
        XCTAssertEqual(vm.resendCooldownRemainingSeconds, 0)
        XCTAssertFalse(vm.canSendEmail) // not configured
        XCTAssertEqual(vm.errorMessage, AppError.auth(.notConfigured).userMessage)
        XCTAssertEqual(repo.sendOTPCallCount, 0)
    }

    func testBackToEmailEntryKeepsCooldown() async {
        let repo = MockAuthRepository()
        let vm = AuthViewModel(repository: repo, isConfigured: true, autoTickResendCooldown: false)
        vm.emailInput = "user@example.com"
        await vm.sendOTP()
        XCTAssertEqual(vm.phase, .awaitingOTP(email: "user@example.com"))
        vm.backToEmailEntry()
        XCTAssertEqual(vm.phase, .signedOut)
        XCTAssertGreaterThan(vm.resendCooldownRemainingSeconds, 0)
        XCTAssertFalse(vm.canSendEmail)
    }
}
