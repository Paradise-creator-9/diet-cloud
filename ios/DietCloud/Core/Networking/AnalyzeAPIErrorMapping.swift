import Foundation

/// Maps analyze-meal HTTP / server errors to safe user-facing copy.
/// Never forwards raw JSON parser dumps, tokens, or base64.
enum AnalyzeAPIErrorMapping {
    static let malformedAIResponseMessage = "AI 返回格式异常，请重试或换一张照片。"
    static let aiUnavailableMessage = "AI 服务暂时不可用。"
    static let imageTooLargeMessage = "图片过大，请换小图。"

    /// Whether a server/transport message looks like a technical JSON parse dump
    /// (Node/V8 or similar) that must not be shown to users.
    static func isTechnicalJSONParseMessage(_ message: String) -> Bool {
        let lower = message.lowercased()
        if lower.contains("expected") && lower.contains("json") { return true }
        if lower.contains("after array element") { return true }
        if lower.contains("after property value") { return true }
        if lower.contains("unexpected token") && (lower.contains("json") || lower.contains("position")) {
            return true
        }
        if lower.contains("unexpected end of json") { return true }
        if lower.contains("json parse") || lower.contains("jsonparse") { return true }
        // Node often includes "at position N" / "line N column M" with JSON syntax errors.
        if lower.contains("in json at position") { return true }
        if lower.contains("line ") && lower.contains("column ") && lower.contains("json") {
            return true
        }
        return false
    }

    static func mapHTTPFailure(statusCode: Int, bodyMessage: String) -> AppError {
        let sanitized = AuthErrorSanitizer.sanitize(bodyMessage)
        switch statusCode {
        case 401, 403:
            return .unauthorized
        case 413:
            return .server(statusCode: 413, message: imageTooLargeMessage)
        case 429:
            return .rateLimited(retryAfterSeconds: nil)
        case 500, 502, 503, 504:
            if isTechnicalJSONParseMessage(sanitized)
                || sanitized.localizedCaseInsensitiveContains("internal server error")
                || sanitized.isEmpty {
                // Image mode often fails when Gemini returns slightly-invalid JSON;
                // backend extractJson is fragile — do not surface the raw parse dump.
                if isTechnicalJSONParseMessage(sanitized) {
                    return .server(statusCode: statusCode, message: malformedAIResponseMessage)
                }
                return .server(statusCode: statusCode, message: aiUnavailableMessage)
            }
            return .server(statusCode: statusCode, message: sanitized)
        case 400 ..< 500:
            if isTechnicalJSONParseMessage(sanitized) {
                return .server(statusCode: statusCode, message: malformedAIResponseMessage)
            }
            let msg = sanitized.isEmpty ? "请求无效。" : sanitized
            return .server(statusCode: statusCode, message: msg)
        default:
            if isTechnicalJSONParseMessage(sanitized) {
                return .server(statusCode: statusCode, message: malformedAIResponseMessage)
            }
            return AppError.fromHTTP(statusCode: statusCode, bodyMessage: sanitized)
        }
    }

    /// Maps any analyze failure (including AppError.server with technical body) to a safe AppError.
    static func map(_ error: Error) -> AppError {
        if let app = error as? AppError {
            switch app {
            case .server(let code, let message):
                if isTechnicalJSONParseMessage(message) {
                    return .server(statusCode: code, message: malformedAIResponseMessage)
                }
                return app
            case .unknown(let message):
                if isTechnicalJSONParseMessage(message) {
                    return .unknown(message: malformedAIResponseMessage)
                }
                return app
            case .network(let message):
                if isTechnicalJSONParseMessage(message) {
                    return .network(message: "网络请求失败，请检查连接后重试。")
                }
                return app
            default:
                return app
            }
        }
        let raw = AuthErrorSanitizer.sanitize(error.localizedDescription)
        if isTechnicalJSONParseMessage(raw) {
            return .unknown(message: malformedAIResponseMessage)
        }
        return DataErrorMapping.map(error)
    }
}
