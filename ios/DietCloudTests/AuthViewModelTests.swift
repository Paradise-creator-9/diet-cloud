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
        await repo.setSession(
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

    func testSendOTPSuccessMovesToAwaitingOTP() async {
        let repo = MockAuthRepository()
        let vm = AuthViewModel(repository: repo, isConfigured: true)
        vm.emailInput = "User@Example.com"
        await vm.sendOTP()
        XCTAssertEqual(vm.phase, .awaitingOTP(email: "user@example.com"))
        let count = await repo.sendOTPCallCount
        XCTAssertEqual(count, 1)
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
        await repo.setVerifyError(AppError.auth(.invalidOTP))
        let vm = AuthViewModel(repository: repo, isConfigured: true)
        vm.emailInput = "user@example.com"
        await vm.sendOTP()
        vm.otpInput = "000000"
        await vm.verifyOTP()
        XCTAssertEqual(vm.phase, .awaitingOTP(email: "user@example.com"))
        XCTAssertEqual(vm.errorMessage, AppError.auth(.invalidOTP).userMessage)
    }

    func testSignOutReturnsToSignedOut() async {
        let repo = MockAuthRepository()
        let user = AuthUser(id: "abc", email: "user@example.com")
        await repo.setSession(
            AuthSessionSnapshot(user: user, expiresAt: Date().addingTimeInterval(3600))
        )
        let vm = AuthViewModel(repository: repo, isConfigured: true)
        await vm.bootstrap()
        await vm.signOut()
        XCTAssertEqual(vm.phase, .signedOut)
        let count = await repo.signOutCallCount
        XCTAssertEqual(count, 1)
        let session = await repo.session
        XCTAssertNil(session)
    }

    func testInvalidEmailDoesNotCallRepository() async {
        let repo = MockAuthRepository()
        let vm = AuthViewModel(repository: repo, isConfigured: true)
        vm.emailInput = "not-an-email"
        await vm.sendOTP()
        XCTAssertEqual(vm.phase, .signedOut)
        XCTAssertEqual(vm.errorMessage, AppError.auth(.invalidEmail).userMessage)
        let count = await repo.sendOTPCallCount
        XCTAssertEqual(count, 0)
    }
}

// Helpers to mutate actor state from tests without exposing setters on production types.
extension MockAuthRepository {
    func setSession(_ value: AuthSessionSnapshot?) {
        session = value
    }

    func setVerifyError(_ error: Error?) {
        verifyOTPError = error
    }
}
