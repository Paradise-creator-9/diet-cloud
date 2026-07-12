import Foundation

enum DataErrorMapping {
    static func map(_ error: Error) -> AppError {
        if let app = error as? AppError { return app }
        let raw = AuthErrorSanitizer.sanitize(error.localizedDescription)
        let lower = raw.lowercased()
        if lower.contains("jwt") || lower.contains("not authenticated") || lower.contains("401") {
            return .unauthorized
        }
        if lower.contains("network") || lower.contains("offline") || lower.contains("timed out") {
            return .network(message: raw.isEmpty ? "网络请求失败。" : raw)
        }
        if lower.contains("permission") || lower.contains("row-level") || lower.contains("rls") {
            return .unauthorized
        }
        return .unknown(message: raw.isEmpty ? "数据操作失败。" : raw)
    }
}
