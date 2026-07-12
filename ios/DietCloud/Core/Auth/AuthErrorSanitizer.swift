import Foundation

enum AuthErrorSanitizer {
    /// Strip JWT-like strings and long secrets before showing errors to users or tests.
    static func sanitize(_ raw: String) -> String {
        var message = raw
        // JWT: header.payload.signature
        if let regex = try? NSRegularExpression(
            pattern: #"eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+"#,
            options: []
        ) {
            message = regex.stringByReplacingMatches(
                in: message,
                options: [],
                range: NSRange(message.startIndex..., in: message),
                withTemplate: "[redacted-token]"
            )
        }
        // Long opaque tokens (32+ url-safe chars)
        if let regex = try? NSRegularExpression(pattern: #"[A-Za-z0-9_-]{40,}"#, options: []) {
            message = regex.stringByReplacingMatches(
                in: message,
                options: [],
                range: NSRange(message.startIndex..., in: message),
                withTemplate: "[redacted]"
            )
        }
        return message
    }

    static func mapAuthFailure(_ error: Error) -> AppError {
        if let app = error as? AppError {
            return app
        }
        let raw = sanitize(error.localizedDescription)
        let lower = raw.lowercased()
        if lower.contains("rate") || lower.contains("too many") || lower.contains("security purposes") {
            return .rateLimited(retryAfterSeconds: nil)
        }
        if lower.contains("invalid") && (lower.contains("otp") || lower.contains("token") || lower.contains("code")) {
            return .auth(.invalidOTP)
        }
        if lower.contains("expired") {
            return .auth(.sessionExpired)
        }
        if lower.contains("network") || lower.contains("offline") || lower.contains("internet") {
            return .network(message: "网络请求失败，请检查连接后重试。")
        }
        return .auth(.provider(message: raw.isEmpty ? "认证失败。" : raw))
    }
}
