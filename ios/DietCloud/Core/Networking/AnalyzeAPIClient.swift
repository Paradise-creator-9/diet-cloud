import Foundation

/// Client for Vercel Gemini analysis via `/api/analyze-meal` and `/api/analyze-body`.
/// Never embeds `GEMINI_API_KEY`; uses Supabase session Bearer token only.
protocol AnalyzeAPIClienting: Sendable {
    func analyzeMealURL() -> URL
    func analyzeBodyURL() -> URL
    func analyzeMeal(_ request: MealAnalysisRequest) async throws -> MealAnalysisResult
    func analyzeBody(_ request: BodyAnalysisRequest) async throws -> BodyAnalysisResult
}

struct AnalyzeAPIClient: AnalyzeAPIClienting {
    private let apiBaseURL: URL
    private let tokenProvider: AccessTokenProviding
    private let httpSession: HTTPSessioning
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        apiBaseURL: URL,
        tokenProvider: AccessTokenProviding,
        httpSession: HTTPSessioning = URLSession.shared
    ) {
        self.apiBaseURL = apiBaseURL
        self.tokenProvider = tokenProvider
        self.httpSession = httpSession
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    init(provider: SupabaseClientProviding, tokenProvider: AccessTokenProviding) {
        self.init(apiBaseURL: provider.config.apiBaseURL, tokenProvider: tokenProvider)
    }

    func analyzeMealURL() -> URL {
        apiBaseURL.appending(path: "api/analyze-meal")
    }

    func analyzeBodyURL() -> URL {
        apiBaseURL.appending(path: "api/analyze-body")
    }

    func analyzeMeal(_ request: MealAnalysisRequest) async throws -> MealAnalysisResult {
        guard !request.containsRemotePhotoURL else {
            throw AppError.unknown(message: "AI 分析不支持远程图片地址，请使用本地照片。")
        }

        let data = try await postJSON(url: analyzeMealURL(), body: request)
        return try decodeMealSuccess(data)
    }

    func analyzeBody(_ request: BodyAnalysisRequest) async throws -> BodyAnalysisResult {
        // Only in-memory data URLs — never remote signed/public URLs or file paths.
        guard request.isLocalDataURL, !request.containsRemotePhotoURL else {
            throw AppError.unknown(message: "AI 分析不支持远程图片地址，请使用本地照片。")
        }

        let data = try await postJSON(url: analyzeBodyURL(), body: request)
        return try decodeBodySuccess(data)
    }

    private func postJSON<Body: Encodable>(url: URL, body: Body) async throws -> Data {
        let token = try await requireBearerToken()
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.timeoutInterval = 60
        urlRequest.httpBody = try encoder.encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await httpSession.data(for: urlRequest)
        } catch {
            throw mapTransportError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AppError.network(message: "网络响应无效。")
        }

        if (200 ... 299).contains(http.statusCode) {
            return data
        }
        throw mapHTTPFailure(statusCode: http.statusCode, data: data)
    }

    private func requireBearerToken() async throws -> String {
        let token: String?
        do {
            token = try await tokenProvider.currentAccessToken()
        } catch {
            throw AppError.unauthorized
        }
        guard let token, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.unauthorized
        }
        return token
    }

    private func decodeMealSuccess(_ data: Data) throws -> MealAnalysisResult {
        let dto: MealAnalysisAPIResponseDTO
        do {
            dto = try decoder.decode(MealAnalysisAPIResponseDTO.self, from: data)
        } catch {
            throw AppError.unknown(message: "AI 返回格式无效。")
        }
        do {
            return try MealAnalysisDTOMapper.domain(from: dto)
        } catch let app as AppError {
            throw app
        } catch {
            throw AppError.unknown(message: "AI 返回格式无效。")
        }
    }

    private func decodeBodySuccess(_ data: Data) throws -> BodyAnalysisResult {
        let dto: BodyAnalysisAPIResponseDTO
        do {
            dto = try decoder.decode(BodyAnalysisAPIResponseDTO.self, from: data)
        } catch {
            throw AppError.unknown(message: "AI 返回格式无效。")
        }
        do {
            return try BodyAnalysisDTOMapper.domain(from: dto)
        } catch let app as AppError {
            throw app
        } catch {
            throw AppError.unknown(message: "AI 返回格式无效。")
        }
    }

    private func mapHTTPFailure(statusCode: Int, data: Data) -> AppError {
        let bodyMessage = Self.extractErrorMessage(from: data)
        return AnalyzeAPIErrorMapping.mapHTTPFailure(statusCode: statusCode, bodyMessage: bodyMessage)
    }

    private func mapTransportError(_ error: Error) -> AppError {
        if let app = error as? AppError { return AnalyzeAPIErrorMapping.map(app) }
        let raw = AuthErrorSanitizer.sanitize(error.localizedDescription)
        if AnalyzeAPIErrorMapping.isTechnicalJSONParseMessage(raw) {
            return .unknown(message: AnalyzeAPIErrorMapping.malformedAIResponseMessage)
        }
        let lower = raw.lowercased()
        if lower.contains("timed out") || lower.contains("timeout") {
            return .network(message: "AI 分析超时，请稍后再试。")
        }
        if lower.contains("network") || lower.contains("offline") || lower.contains("internet")
            || lower.contains("not connected") || lower.contains("could not connect") {
            return .network(message: "网络请求失败，请检查连接后重试。")
        }
        return .network(message: raw.isEmpty ? "网络请求失败。" : raw)
    }

    /// Parses `{ "error": "..." }` without retaining full response bodies that may be large.
    static func extractErrorMessage(from data: Data) -> String {
        guard !data.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = obj["error"] as? String
        else {
            return ""
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        return AuthErrorSanitizer.sanitize(trimmed)
    }
}

// MARK: - Mock (tests)

final class MockAnalyzeAPIClient: AnalyzeAPIClienting, @unchecked Sendable {
    private let lock = NSLock()
    private var _lastRequest: MealAnalysisRequest?
    private var _lastBodyRequest: BodyAnalysisRequest?
    private var _callCount = 0
    private var _bodyCallCount = 0
    private var _result: MealAnalysisResult?
    private var _bodyResult: BodyAnalysisResult?
    private var _error: Error?
    private var _bodyError: Error?
    private let mealURL: URL
    private let bodyURL: URL

    var lastRequest: MealAnalysisRequest? {
        lock.lock(); defer { lock.unlock() }
        return _lastRequest
    }

    var lastBodyRequest: BodyAnalysisRequest? {
        lock.lock(); defer { lock.unlock() }
        return _lastBodyRequest
    }

    var callCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _callCount
    }

    var bodyCallCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _bodyCallCount
    }

    init(
        mealURL: URL = URL(string: "https://example.invalid/api/analyze-meal")!,
        bodyURL: URL = URL(string: "https://example.invalid/api/analyze-body")!
    ) {
        self.mealURL = mealURL
        self.bodyURL = bodyURL
    }

    func setResult(_ result: MealAnalysisResult?) {
        lock.lock(); defer { lock.unlock() }
        _result = result
    }

    func setBodyResult(_ result: BodyAnalysisResult?) {
        lock.lock(); defer { lock.unlock() }
        _bodyResult = result
    }

    func setError(_ error: Error?) {
        lock.lock(); defer { lock.unlock() }
        _error = error
    }

    func setBodyError(_ error: Error?) {
        lock.lock(); defer { lock.unlock() }
        _bodyError = error
    }

    func analyzeMealURL() -> URL { mealURL }
    func analyzeBodyURL() -> URL { bodyURL }

    func analyzeMeal(_ request: MealAnalysisRequest) async throws -> MealAnalysisResult {
        lock.lock()
        _callCount += 1
        _lastRequest = request
        let error = _error
        let result = _result
        lock.unlock()

        if let error { throw error }
        if let result { return result }
        return MealAnalysisResult(
            dishName: "Mock 餐食",
            confidence: 0.8,
            total: MealAnalysisNutrition(
                grams: 100, calories: 200, protein: 10, carbs: 20, fat: 5, fiber: 1
            ),
            items: [],
            notes: "mock",
            model: "mock-model"
        )
    }

    func analyzeBody(_ request: BodyAnalysisRequest) async throws -> BodyAnalysisResult {
        lock.lock()
        _bodyCallCount += 1
        _lastBodyRequest = request
        let error = _bodyError
        let result = _bodyResult
        lock.unlock()

        if let error { throw error }
        if let result { return result }
        return BodyAnalysisResult(
            confidence: 0.8,
            date: nil,
            measuredAt: nil,
            score: nil,
            weightKg: 70,
            bmi: 22,
            bodyFatPercent: 18,
            bodyAge: nil,
            bodyType: nil,
            muscleKg: 50,
            skeletalMuscleKg: nil,
            boneMassKg: 3,
            waterPercent: 55,
            visceralFat: 8,
            bmrKcal: 1500,
            proteinPercent: nil,
            trunkFatPercent: nil,
            trunkMuscleKg: nil,
            leftArmFatPercent: nil,
            leftArmMuscleKg: nil,
            rightArmFatPercent: nil,
            rightArmMuscleKg: nil,
            leftLegFatPercent: nil,
            leftLegMuscleKg: nil,
            rightLegFatPercent: nil,
            rightLegMuscleKg: nil,
            notes: "mock body",
            model: "mock-model"
        )
    }
}
