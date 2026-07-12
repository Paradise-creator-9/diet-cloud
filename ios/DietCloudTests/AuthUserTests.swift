import XCTest
@testable import DietCloud

final class AuthUserTests: XCTestCase {
    func testRedactedEmail() {
        let user = AuthUser(id: "1", email: "alice@example.com")
        XCTAssertEqual(user.redactedEmail, "a***@example.com")
    }

    func testSessionExpiry() {
        let expired = AuthSessionSnapshot(
            user: AuthUser(id: "1", email: "a@b.com"),
            expiresAt: Date().addingTimeInterval(-10)
        )
        XCTAssertTrue(expired.isExpired)

        let fresh = AuthSessionSnapshot(
            user: AuthUser(id: "1", email: "a@b.com"),
            expiresAt: Date().addingTimeInterval(600)
        )
        XCTAssertFalse(fresh.isExpired)
    }
}
