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
    }

    func testUserMessageNeverEmpty() {
        let errors: [AppError] = [
            .configuration(.missingKey("X")),
            .configuration(.invalidURL(key: "U", value: "v")),
            .configuration(.placeholderConfig),
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
