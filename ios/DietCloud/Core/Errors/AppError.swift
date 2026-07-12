import Foundation

/// Unified app-facing errors. Map network / auth / config failures here
/// without leaking secrets into messages.
enum AppError: Error, Equatable, Sendable {
    case configuration(ConfigurationIssue)
    case auth(AuthIssue)
    case notImplemented(String)
    case unauthorized
    case rateLimited(retryAfterSeconds: Int?)
    case network(message: String)
    case server(statusCode: Int, message: String)
    case unknown(message: String)

    enum ConfigurationIssue: Equatable, Sendable {
        case missingKey(String)
        case invalidURL(key: String, value: String)
        case placeholderConfig
    }

    enum AuthIssue: Equatable, Sendable {
        case notConfigured
        case invalidEmail
        case invalidOTP
        case sessionExpired
        case keychain(status: Int)
        case provider(message: String)
    }

    var code: String {
        switch self {
        case .configuration: return "configuration"
        case .auth: return "auth"
        case .notImplemented: return "not_implemented"
        case .unauthorized: return "unauthorized"
        case .rateLimited: return "rate_limited"
        case .network: return "network"
        case .server: return "server"
        case .unknown: return "unknown"
        }
    }

    /// User-visible Chinese copy; never includes tokens or API keys.
    var userMessage: String {
        switch self {
        case .configuration(.missingKey(let key)):
            return "缺少配置项 \(key)。请检查 xcconfig / Info.plist。"
        case .configuration(.invalidURL(let key, _)):
            return "配置项 \(key) 不是有效的 URL。"
        case .configuration(.placeholderConfig):
            return "仍在使用占位配置。请在 Secrets.xcconfig 中填写真实的 Supabase URL 与 anon key。"
        case .auth(.notConfigured):
            return "Supabase 尚未配置，无法登录。"
        case .auth(.invalidEmail):
            return "请输入有效的邮箱地址。"
        case .auth(.invalidOTP):
            return "验证码不正确或已过期，请重试。"
        case .auth(.sessionExpired):
            return "登录已过期，请重新登录。"
        case .auth(.keychain):
            return "无法安全保存登录状态，请重试。"
        case .auth(.provider(let message)):
            let safe = AuthErrorSanitizer.sanitize(message)
            return safe.isEmpty ? "认证失败。" : safe
        case .notImplemented(let feature):
            return "「\(feature)」尚未实现。"
        case .unauthorized:
            return "登录已失效或未授权，请重新登录。"
        case .rateLimited:
            return "请求过于频繁，请稍后再试。"
        case .network(let message):
            return message.isEmpty ? "网络请求失败。" : AuthErrorSanitizer.sanitize(message)
        case .server(_, let message):
            return message.isEmpty ? "服务暂时不可用。" : AuthErrorSanitizer.sanitize(message)
        case .unknown(let message):
            return message.isEmpty ? "发生未知错误。" : AuthErrorSanitizer.sanitize(message)
        }
    }

    /// Map HTTP status from analyze-* (and similar) responses.
    static func fromHTTP(statusCode: Int, bodyMessage: String? = nil) -> AppError {
        let message = bodyMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch statusCode {
        case 401, 403:
            return .unauthorized
        case 413:
            return .server(statusCode: 413, message: "图片过大，请换小图。")
        case 429:
            return .rateLimited(retryAfterSeconds: nil)
        case 500, 502, 503, 504:
            return .server(
                statusCode: statusCode,
                message: message.isEmpty ? "AI 服务暂时不可用。" : message
            )
        case 400 ..< 500:
            return .server(statusCode: statusCode, message: message.isEmpty ? "请求无效。" : message)
        case 500 ..< 600:
            return .server(statusCode: statusCode, message: message.isEmpty ? "服务暂时不可用。" : message)
        default:
            return .unknown(message: message.isEmpty ? "Unexpected status \(statusCode)." : message)
        }
    }
}
