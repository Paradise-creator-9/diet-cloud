import XCTest
@testable import DietCloud

final class AppErrorTests: XCTestCase {
    func testHTTPMapping() {
        XCTAssertEqual(AppError.fromHTTP(statusCode: 401).code, "unauthorized")
        XCTAssertEqual(AppError.fromHTTP(statusCode: 403).code, "unauthorized")
        XCTAssertEqual(AppError.fromHTTP(statusCode: 429).code, "rate_limited")
        XCTAssertEqual(AppError.fromHTTP(statusCode: 500).code, "server")

        if case .server(let code, let message) = AppError.fromHTTP(statusCode: 400, bodyMessage: "bad") {
            XCTAssertEqual(code, 400)
            XCTAssertEqual(message, "bad")
        } else {
            XCTFail("Expected server error")
        }

        if case .server(let code, let message) = AppError.fromHTTP(statusCode: 413) {
            XCTAssertEqual(code, 413)
            XCTAssertEqual(message, "图片过大，请换小图。")
        } else {
            XCTFail("Expected 413 mapping")
        }

        if case .server(_, let message) = AppError.fromHTTP(statusCode: 503) {
            XCTAssertEqual(message, "AI 服务暂时不可用。")
        } else {
            XCTFail("Expected 503 mapping")
        }
    }

    func testUserMessageNeverEmpty() {
        let errors: [AppError] = [
            .configuration(.missingKey("X")),
            .configuration(.invalidURL(key: "U", value: "v")),
            .configuration(.placeholderConfig),
            .auth(.notConfigured),
            .auth(.invalidEmail),
            .auth(.invalidOTP),
            .auth(.sessionExpired),
            .auth(.keychain(status: -1)),
            .auth(.provider(message: "eyJhbGciOiJIUzI1NiJ9.payload.sig")),
            .notImplemented("Auth"),
            .unauthorized,
            .rateLimited(retryAfterSeconds: 12),
            .network(message: ""),
            .server(statusCode: 500, message: ""),
            .unknown(message: ""),
        ]

        for error in errors {
            XCTAssertFalse(error.userMessage.isEmpty, "Empty message for \(error)")
            XCTAssertFalse(error.userMessage.lowercased().contains("service_role"))
            XCTAssertFalse(error.userMessage.lowercased().contains("gemini_api_key"))
            XCTAssertFalse(error.userMessage.lowercased().contains("diary_ingest_token"))
        }
    }
}
