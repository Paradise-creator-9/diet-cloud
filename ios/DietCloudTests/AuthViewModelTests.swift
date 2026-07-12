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
}
