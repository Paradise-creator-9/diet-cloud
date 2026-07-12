import XCTest
@testable import DietCloud

// MARK: - Mock HTTP

final class MockHTTPSession: HTTPSessioning, @unchecked Sendable {
    private let lock = NSLock()
    private var _statusCode = 200
    private var _body = Data()
    private var _error: Error?
    private(set) var lastRequest: URLRequest?

    func setResponse(statusCode: Int, json: [String: Any]) {
        lock.lock(); defer { lock.unlock() }
        _statusCode = statusCode
        _body = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
        _error = nil
    }

    func setResponse(statusCode: Int, rawBody: Data) {
        lock.lock(); defer { lock.unlock() }
        _statusCode = statusCode
        _body = rawBody
        _error = nil
    }

    func setTransportError(_ error: Error) {
        lock.lock(); defer { lock.unlock() }
        _error = error
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lock.lock()
        lastRequest = request
        let status = _statusCode
        let body = _body
        let error = _error
        lock.unlock()
        if let error { throw error }
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.invalid")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (body, response)
    }
}

// MARK: - Tests

final class AnalyzeAPIClientTests: XCTestCase {
    private let baseURL = URL(string: "https://example.invalid")!

    private func makeClient(
        token: String? = "test-access-token-not-a-secret",
        session: MockHTTPSession
    ) -> AnalyzeAPIClient {
        AnalyzeAPIClient(
            apiBaseURL: baseURL,
            tokenProvider: FixedAccessTokenProvider(token: token),
            httpSession: session
        )
    }

    func testTextOnlyRequestBodyAndBearerHeader() async throws {
        let session = MockHTTPSession()
        session.setResponse(statusCode: 200, json: Self.successJSON())
        let client = makeClient(session: session)

        let request = try MealAnalysisRequest.make(hint: "一碗牛肉饭", jpegData: nil)
        let result = try await client.analyzeMeal(request)

        XCTAssertEqual(result.dishName, "牛肉饭")
        let httpRequest = session.lastRequest
        XCTAssertEqual(httpRequest?.httpMethod, "POST")
        XCTAssertEqual(httpRequest?.url?.absoluteString, "https://example.invalid/api/analyze-meal")
        XCTAssertEqual(httpRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer test-access-token-not-a-secret")
        XCTAssertTrue(httpRequest?.value(forHTTPHeaderField: "Content-Type")?.contains("application/json") == true)
        XCTAssertNil(httpRequest?.url?.query)

        let body = try XCTUnwrap(httpRequest?.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(json?["hint"] as? String, "一碗牛肉饭")
        let photos = json?["photos"] as? [Any]
        XCTAssertEqual(photos?.count, 0)
        let bodyString = String(data: body, encoding: .utf8) ?? ""
        XCTAssertFalse(bodyString.contains("https://"))
        XCTAssertFalse(bodyString.lowercased().contains("signed"))
    }

    func testPhotoRequestBodyIsDataURLNotSignedURL() async throws {
        let session = MockHTTPSession()
        session.setResponse(statusCode: 200, json: Self.successJSON(dish: "煎蛋"))
        let client = makeClient(session: session)
        let jpeg = Data(repeating: 0xAB, count: 32)
        let request = try MealAnalysisRequest.make(hint: "两个蛋", jpegData: jpeg)
        _ = try await client.analyzeMeal(request)

        let body = try XCTUnwrap(session.lastRequest?.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let photos = try XCTUnwrap(json?["photos"] as? [[String: Any]])
        XCTAssertEqual(photos.count, 1)
        XCTAssertEqual(photos[0]["contentType"] as? String, "image/jpeg")
        let dataUrl = try XCTUnwrap(photos[0]["dataUrl"] as? String)
        XCTAssertTrue(dataUrl.hasPrefix("data:image/jpeg;base64,"))
        XCTAssertFalse(dataUrl.hasPrefix("http"))
        XCTAssertEqual(json?["hint"] as? String, "两个蛋")
        XCTAssertFalse(request.containsRemotePhotoURL)
    }

    func testMissingTokenDoesNotSendRequest() async {
        let session = MockHTTPSession()
        session.setResponse(statusCode: 200, json: Self.successJSON())
        let client = makeClient(token: nil, session: session)
        do {
            _ = try await client.analyzeMeal(try MealAnalysisRequest.make(hint: "饭", jpegData: nil))
            XCTFail("expected unauthorized")
        } catch let error as AppError {
            XCTAssertEqual(error, .unauthorized)
            XCTAssertNil(session.lastRequest)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testEmptyTokenDoesNotSendRequest() async {
        let session = MockHTTPSession()
        let client = makeClient(token: "   ", session: session)
        do {
            _ = try await client.analyzeMeal(try MealAnalysisRequest.make(hint: "饭", jpegData: nil))
            XCTFail("expected unauthorized")
        } catch let error as AppError {
            XCTAssertEqual(error, .unauthorized)
            XCTAssertNil(session.lastRequest)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testHTTP401MapsToUnauthorized() async {
        await assertStatus(401, json: ["error": "Invalid or expired session."]) { error in
            XCTAssertEqual(error, .unauthorized)
            XCTAssertFalse(error.userMessage.contains("eyJ"))
        }
    }

    func testHTTP413MapsToImageTooLarge() async {
        await assertStatus(413, json: ["error": "Payload too large"]) { error in
            if case .server(let code, let message) = error {
                XCTAssertEqual(code, 413)
                XCTAssertEqual(message, "图片过大，请换小图。")
            } else {
                XCTFail("expected 413 server error")
            }
        }
    }

    func testHTTP429MapsToRateLimited() async {
        await assertStatus(429, json: ["error": "AI 分析请求过于频繁，请稍后再试。", "code": "rate_limited"]) { error in
            if case .rateLimited = error {
                XCTAssertEqual(error.userMessage, AppError.rateLimited(retryAfterSeconds: nil).userMessage)
            } else {
                XCTFail("expected rate limited")
            }
        }
    }

    func testHTTP500MapsToAIUnavailable() async {
        await assertStatus(500, json: ["error": ""]) { error in
            if case .server(let code, let message) = error {
                XCTAssertEqual(code, 500)
                XCTAssertEqual(message, "AI 服务暂时不可用。")
            } else {
                XCTFail("expected server")
            }
        }
    }

    func testHTTP502And503MapToAIUnavailable() async {
        await assertStatus(502, json: [:]) { error in
            if case .server(let code, let message) = error {
                XCTAssertEqual(code, 502)
                XCTAssertTrue(message.contains("AI") || message.contains("不可用"))
            } else {
                XCTFail("expected 502")
            }
        }
        await assertStatus(503, json: [:]) { error in
            if case .server(let code, _) = error {
                XCTAssertEqual(code, 503)
            } else {
                XCTFail("expected 503")
            }
        }
    }

    func testMalformedSuccessBodyIsSafeError() async {
        let session = MockHTTPSession()
        session.setResponse(statusCode: 200, rawBody: Data("not-json".utf8))
        let client = makeClient(session: session)
        do {
            _ = try await client.analyzeMeal(try MealAnalysisRequest.make(hint: "饭", jpegData: nil))
            XCTFail("expected error")
        } catch let error as AppError {
            XCTAssertEqual(error.userMessage, "AI 返回格式无效。")
            XCTAssertFalse(error.userMessage.contains("base64"))
            XCTAssertFalse(error.userMessage.contains("Bearer"))
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testMissingAnalysisFieldIsSafeError() async {
        let session = MockHTTPSession()
        session.setResponse(statusCode: 200, json: ["ok": true, "model": "x"])
        let client = makeClient(session: session)
        do {
            _ = try await client.analyzeMeal(try MealAnalysisRequest.make(hint: "饭", jpegData: nil))
            XCTFail("expected error")
        } catch let error as AppError {
            XCTAssertEqual(error.userMessage, "AI 返回格式无效。")
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testErrorBodyWithTokenIsSanitized() async {
        let jwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.payload.signature"
        await assertStatus(500, json: ["error": "upstream failed token \(jwt)"]) { error in
            XCTAssertFalse(error.userMessage.contains("eyJ"))
            XCTAssertFalse(error.userMessage.contains(jwt))
        }
    }

    func testMissingHintAndPhotoThrowsBeforeNetwork() async {
        let session = MockHTTPSession()
        do {
            _ = try MealAnalysisRequest.make(hint: "  ", jpegData: nil)
            XCTFail("expected empty input error")
        } catch let error as AppError {
            XCTAssertTrue(error.userMessage.contains("文字") || error.userMessage.contains("照片"))
            XCTAssertNil(session.lastRequest)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testAnalyzeURLs() {
        let client = makeClient(session: MockHTTPSession())
        XCTAssertEqual(client.analyzeMealURL().absoluteString, "https://example.invalid/api/analyze-meal")
        XCTAssertEqual(client.analyzeBodyURL().absoluteString, "https://example.invalid/api/analyze-body")
    }

    // MARK: - Helpers

    private func assertStatus(
        _ status: Int,
        json: [String: Any],
        file: StaticString = #filePath,
        line: UInt = #line,
        _ check: (AppError) -> Void
    ) async {
        let session = MockHTTPSession()
        session.setResponse(statusCode: status, json: json)
        let client = makeClient(session: session)
        do {
            _ = try await client.analyzeMeal(try MealAnalysisRequest.make(hint: "饭", jpegData: nil))
            XCTFail("expected error for \(status)", file: file, line: line)
        } catch let error as AppError {
            check(error)
        } catch {
            XCTFail("unexpected \(error)", file: file, line: line)
        }
    }

    private static func successJSON(dish: String = "牛肉饭") -> [String: Any] {
        [
            "ok": true,
            "model": "mock-model",
            "analysis": [
                "dishName": dish,
                "confidence": 0.85,
                "total": [
                    "grams": 300,
                    "calories": 500,
                    "protein": 20,
                    "carbs": 60,
                    "fat": 10,
                    "fiber": 2,
                ],
                "items": [
                    [
                        "name": "米饭",
                        "grams": 200,
                        "calories": 280,
                        "protein": 5,
                        "carbs": 60,
                        "fat": 1,
                        "fiber": 1,
                        "reasoning": "常见份量",
                    ],
                ],
                "notes": "估算结果",
            ] as [String: Any],
        ]
    }
}

final class MealAnalysisMapperTests: XCTestCase {
    func testFormFillMapsTotalsAndNotes() {
        let result = MealAnalysisResult(
            dishName: "咖喱鸡饭",
            confidence: 0.72,
            total: MealAnalysisNutrition(
                grams: 400, calories: 650, protein: 30, carbs: 80, fat: 20, fiber: 4
            ),
            items: [
                MealAnalysisItem(
                    name: "米饭", grams: 200, calories: 280, protein: 5, carbs: 60, fat: 1, fiber: 1, reasoning: ""
                ),
            ],
            notes: "偏大份",
            model: "m"
        )
        let fill = MealAnalysisMapper.formFill(from: result, userHint: "一碗咖喱")
        XCTAssertEqual(fill.name, "咖喱鸡饭")
        XCTAssertEqual(fill.calories, "650")
        XCTAssertEqual(fill.protein, "30")
        XCTAssertTrue(fill.note.contains("用户补充：一碗咖喱"))
        XCTAssertTrue(fill.note.contains("偏大份"))
        XCTAssertTrue(fill.summary.contains("650"))
    }

    func testMissingFieldsGetSafeDefaults() {
        let dto = MealAnalysisDTO(
            dishName: nil,
            confidence: nil,
            total: nil,
            items: nil,
            notes: nil
        )
        let domain = MealAnalysisDTOMapper.domain(from: dto, model: nil)
        XCTAssertEqual(domain.dishName, "AI 识别餐食")
        XCTAssertEqual(domain.total.calories, 0)
        XCTAssertTrue(domain.notes.contains("参考") || !domain.notes.isEmpty)
        let fill = MealAnalysisMapper.formFill(from: domain, userHint: "")
        XCTAssertEqual(fill.name, "AI 识别餐食")
        XCTAssertEqual(fill.calories, "0")
    }
}
