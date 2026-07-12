import XCTest
@testable import DietCloud

final class AuthErrorSanitizerTests: XCTestCase {
    func testSanitizerRedactsJWTLikeStrings() {
        let jwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.signaturepart"
        let raw = "Auth failed token=\(jwt) please retry"
        let cleaned = AuthErrorSanitizer.sanitize(raw)
        XCTAssertFalse(cleaned.contains("eyJhbGci"))
        XCTAssertTrue(cleaned.contains("[redacted"))
    }

    func testAppErrorUserMessageNeverContainsTokenMaterial() {
        let jwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.payload.signature"
        let error = AppError.auth(.provider(message: "invalid refresh \(jwt)"))
        XCTAssertFalse(error.userMessage.contains("eyJ"))
        XCTAssertFalse(error.userMessage.contains(jwt))
    }

    func testMapAuthFailureInvalidOTP() {
        struct E: LocalizedError {
            var errorDescription: String? { "Invalid OTP token provided" }
        }
        let mapped = AuthErrorSanitizer.mapAuthFailure(E())
        XCTAssertEqual(mapped, .auth(.invalidOTP))
    }
}
