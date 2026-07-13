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

    func testHTTP500JSONParseDumpIsSanitized() async {
        let dump = "Expected ',' or ']' after array element in JSON at position 1424 (line 72 column 6)"
        await assertStatus(500, json: ["error": dump]) { error in
            XCTAssertEqual(error.userMessage, AnalyzeAPIErrorMapping.malformedAIResponseMessage)
            XCTAssertFalse(error.userMessage.contains("position"))
            XCTAssertFalse(error.userMessage.contains("array element"))
            XCTAssertFalse(error.userMessage.contains("1424"))
        }
    }

    func testInternalServerErrorIsFriendly() async {
        await assertStatus(500, json: ["error": "Internal server error.", "code": "internal_error"]) { error in
            XCTAssertEqual(error.userMessage, AnalyzeAPIErrorMapping.aiUnavailableMessage)
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

    // MARK: - Body analyze (Stage 16)

    func testBodyRequestIsDataURLAndHitsAnalyzeBody() async throws {
        let session = MockHTTPSession()
        session.setResponse(statusCode: 200, json: Self.bodySuccessJSON())
        let client = makeClient(session: session)
        let jpeg = Data(repeating: 0xCD, count: 24)
        let request = try BodyAnalysisRequest.make(jpegData: jpeg)
        let result = try await client.analyzeBody(request)

        XCTAssertEqual(result.weightKg, 72.5)
        XCTAssertEqual(session.lastRequest?.url?.absoluteString, "https://example.invalid/api/analyze-body")
        XCTAssertEqual(
            session.lastRequest?.value(forHTTPHeaderField: "Authorization"),
            "Bearer test-access-token-not-a-secret"
        )
        let body = try XCTUnwrap(session.lastRequest?.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let screenshot = try XCTUnwrap(json?["screenshot"] as? [String: Any])
        let dataUrl = try XCTUnwrap(screenshot["dataUrl"] as? String)
        XCTAssertTrue(dataUrl.hasPrefix("data:image/jpeg;base64,"))
        XCTAssertFalse(dataUrl.hasPrefix("http"))
    }

    func testBodyRejectsRemoteHTTPURLBeforeNetwork() async {
        let session = MockHTTPSession()
        let client = makeClient(session: session)
        let remote = BodyAnalysisRequest(
            screenshot: BodyAnalysisScreenshotPayload(
                fileName: "x.jpg",
                contentType: "image/jpeg",
                dataUrl: "https://cdn.example/body.jpg"
            )
        )
        do {
            _ = try await client.analyzeBody(remote)
            XCTFail("expected reject")
        } catch let error as AppError {
            XCTAssertTrue(error.userMessage.contains("本地") || error.userMessage.contains("远程"))
            XCTAssertNil(session.lastRequest)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testBodyHTTP401MapsToUnauthorized() async {
        let session = MockHTTPSession()
        session.setResponse(statusCode: 401, json: ["error": "Invalid session"])
        let client = makeClient(session: session)
        do {
            _ = try await client.analyzeBody(try BodyAnalysisRequest.make(jpegData: Data([0x01])))
            XCTFail("expected 401")
        } catch let error as AppError {
            XCTAssertEqual(error, .unauthorized)
            XCTAssertFalse(error.userMessage.contains("eyJ"))
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testBodyHTTP413And429MapSafely() async {
        let session413 = MockHTTPSession()
        session413.setResponse(statusCode: 413, json: ["error": "too large"])
        let client413 = makeClient(session: session413)
        do {
            _ = try await client413.analyzeBody(try BodyAnalysisRequest.make(jpegData: Data([0x02])))
            XCTFail("expected 413")
        } catch let error as AppError {
            XCTAssertEqual(error.userMessage, AnalyzeAPIErrorMapping.imageTooLargeMessage)
        } catch {
            XCTFail("unexpected \(error)")
        }

        let session429 = MockHTTPSession()
        session429.setResponse(statusCode: 429, json: ["error": "rate limited", "code": "rate_limited"])
        let client429 = makeClient(session: session429)
        do {
            _ = try await client429.analyzeBody(try BodyAnalysisRequest.make(jpegData: Data([0x03])))
            XCTFail("expected 429")
        } catch let error as AppError {
            if case .rateLimited = error {} else {
                XCTFail("expected rateLimited, got \(error)")
            }
            XCTAssertFalse(error.userMessage.contains("base64"))
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    // MARK: - Helpers

    private static func bodySuccessJSON() -> [String: Any] {
        [
            "ok": true,
            "model": "stub",
            "analysis": [
                "confidence": 0.88,
                "date": "2026-07-13",
                "weightKg": 72.5,
                "bmi": 22.0,
                "bodyFatPercent": 18.0,
                "muscleKg": 50.0,
                "boneMassKg": 2.9,
                "waterPercent": 55.0,
                "visceralFat": 7.0,
                "bmrKcal": 1500.0,
                "notes": "请核对",
            ] as [String: Any],
        ]
    }


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

final class AnalyzeAPIErrorMappingTests: XCTestCase {
    func testDetectsNodeStyleJSONParseMessage() {
        let msg = "Expected ',' or ']' after array element in JSON at position 1424 (line 72 column 6)"
        XCTAssertTrue(AnalyzeAPIErrorMapping.isTechnicalJSONParseMessage(msg))
        let mapped = AnalyzeAPIErrorMapping.mapHTTPFailure(statusCode: 500, bodyMessage: msg)
        XCTAssertEqual(mapped.userMessage, AnalyzeAPIErrorMapping.malformedAIResponseMessage)
        XCTAssertFalse(mapped.userMessage.contains("base64"))
        XCTAssertFalse(mapped.userMessage.contains("Bearer"))
    }

    func testDoesNotMisclassifyNormalChineseErrors() {
        XCTAssertFalse(AnalyzeAPIErrorMapping.isTechnicalJSONParseMessage("请上传照片，或者至少填写一句文字说明。"))
        let mapped = AnalyzeAPIErrorMapping.mapHTTPFailure(
            statusCode: 400,
            bodyMessage: "请上传照片，或者至少填写一句文字说明。"
        )
        if case .server(let code, let message) = mapped {
            XCTAssertEqual(code, 400)
            XCTAssertTrue(message.contains("照片") || message.contains("文字"))
        } else {
            XCTFail("expected 400 server")
        }
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
