import Foundation

/// Public client configuration only.
/// Never load SERVICE_ROLE, GEMINI_API_KEY, or DIARY_INGEST_TOKEN into the app.
struct AppConfig: Equatable, Sendable {
    /// Default Magic Link callback when `DIETCLOUD_AUTH_REDIRECT_URL` is omitted.
    /// Must also be added manually in Supabase Dashboard → Auth → Redirect URLs.
    static let defaultAuthRedirectURL = URL(string: "dietcloud://auth-callback")!

    let supabaseURL: URL
    let supabaseAnonKey: String
    let apiBaseURL: URL
    let storageBucket: String
    /// iOS Magic Link redirect (e.g. `dietcloud://auth-callback`). Not a secret.
    let authRedirectURL: URL

    /// Placeholder values from committed xcconfig — not a real project.
    var isPlaceholder: Bool {
        let urlHost = supabaseURL.host?.lowercased() ?? ""
        return urlHost.contains("your_project")
            || urlHost.isEmpty
            || supabaseAnonKey.contains("YOUR_SUPABASE")
            || supabaseAnonKey == "placeholder-anon-key"
            || !isUsableHTTPURL(supabaseURL)
    }

    var isReadyForNetwork: Bool {
        !isPlaceholder
            && !supabaseAnonKey.isEmpty
            && !storageBucket.isEmpty
            && isUsableHTTPURL(supabaseURL)
            && isUsableHTTPURL(apiBaseURL)
            && isUsableAuthRedirectURL(authRedirectURL)
    }

    /// Safe summary for UI — host only, never keys/tokens.
    var safeDiagnostics: String {
        let host = supabaseURL.host?.isEmpty == false ? (supabaseURL.host ?? "—") : "无效 URL"
        let ready = isReadyForNetwork ? "可联网" : "未就绪"
        return "Supabase: \(host) · \(ready)"
    }
}

enum AppConfigKey: String {
    case supabaseURL = "SUPABASE_URL"
    case supabaseAnonKey = "SUPABASE_ANON_KEY"
    case apiBaseURL = "API_BASE_URL"
    case storageBucket = "STORAGE_BUCKET"
    case authRedirectURL = "DIETCLOUD_AUTH_REDIRECT_URL"
}

enum AppConfigLoader {
    /// Load from the app bundle Info.plist (values substituted from xcconfig).
    static func loadFromBundle(_ bundle: Bundle = .main) throws -> AppConfig {
        try load(from: bundle.infoDictionary as [String: Any]? ?? [:])
    }

    /// Load from an explicit dictionary (tests and previews).
    static func load(from dictionary: [String: Any]) throws -> AppConfig {
        let supabaseURLString = try requiredString(AppConfigKey.supabaseURL.rawValue, in: dictionary)
        let apiBaseURLString = try requiredString(AppConfigKey.apiBaseURL.rawValue, in: dictionary)
        let anonKey = try requiredString(AppConfigKey.supabaseAnonKey.rawValue, in: dictionary)
        let bucket = try requiredString(AppConfigKey.storageBucket.rawValue, in: dictionary)

        let supabaseURL = try parseHTTPURL(
            supabaseURLString,
            key: AppConfigKey.supabaseURL.rawValue
        )
        let apiBaseURL = try parseHTTPURL(
            apiBaseURLString,
            key: AppConfigKey.apiBaseURL.rawValue
        )
        guard !anonKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.configuration(.missingKey(AppConfigKey.supabaseAnonKey.rawValue))
        }
        guard !bucket.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.configuration(.missingKey(AppConfigKey.storageBucket.rawValue))
        }

        let authRedirect = try resolveAuthRedirectURL(from: dictionary)

        return AppConfig(
            supabaseURL: supabaseURL,
            supabaseAnonKey: anonKey.trimmingCharacters(in: .whitespacesAndNewlines),
            apiBaseURL: apiBaseURL,
            storageBucket: bucket.trimmingCharacters(in: .whitespacesAndNewlines),
            authRedirectURL: authRedirect
        )
    }

    /// Rejects truncated xcconfig values like `https:` (caused by // comments).
    static func parseHTTPURL(_ raw: String, key: String) throws -> URL {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased() else {
            throw AppError.configuration(.invalidURL(key: key, value: sanitizeURLForError(text)))
        }
        guard scheme == "http" || scheme == "https" else {
            throw AppError.configuration(.invalidURL(key: key, value: sanitizeURLForError(text)))
        }
        // `https:` alone has no host — classic broken xcconfig symptom.
        guard let host = url.host, !host.isEmpty else {
            throw AppError.configuration(.invalidURL(key: key, value: sanitizeURLForError(text)))
        }
        return url
    }

    /// Validates redirect URL: must be an absolute URL with a scheme, no secrets/tokens in query.
    static func resolveAuthRedirectURL(from dictionary: [String: Any]) throws -> URL {
        let key = AppConfigKey.authRedirectURL.rawValue
        let raw: String
        if let value = dictionary[key] {
            let text = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty || text == "$(\(key))" {
                raw = AppConfig.defaultAuthRedirectURL.absoluteString
            } else {
                raw = text
            }
        } else {
            raw = AppConfig.defaultAuthRedirectURL.absoluteString
        }

        guard let url = URL(string: raw), let scheme = url.scheme, !scheme.isEmpty else {
            throw AppError.configuration(.invalidURL(key: key, value: sanitizeURLForError(raw)))
        }

        // Broken xcconfig often yields only `dietcloud:` with no path/host.
        if scheme == "dietcloud" {
            let path = url.host ?? url.path
            if path.isEmpty || path == "/" {
                throw AppError.configuration(.invalidURL(key: key, value: sanitizeURLForError(raw)))
            }
        }

        if let query = url.query?.lowercased(),
           query.contains("token") || query.contains("access_token") || query.contains("refresh_token") {
            throw AppError.configuration(.invalidURL(key: key, value: "[redacted-query]"))
        }

        return url
    }

    private static func requiredString(_ key: String, in dictionary: [String: Any]) throws -> String {
        guard let raw = dictionary[key] else {
            throw AppError.configuration(.missingKey(key))
        }
        let value = String(describing: raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value != "$(\(key))" else {
            throw AppError.configuration(.missingKey(key))
        }
        return value
    }

    /// Never put full secrets into error surfaces.
    private static func sanitizeURLForError(_ raw: String) -> String {
        if raw.count <= 12 { return raw }
        if raw.hasPrefix("http") || raw.hasPrefix("dietcloud") {
            return String(raw.prefix(12)) + "…"
        }
        return "[redacted]"
    }
}

private func isUsableHTTPURL(_ url: URL) -> Bool {
    guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
        return false
    }
    return !(url.host ?? "").isEmpty
}

private func isUsableAuthRedirectURL(_ url: URL) -> Bool {
    guard let scheme = url.scheme, !scheme.isEmpty else { return false }
    if scheme == "dietcloud" {
        let path = url.host ?? url.path
        return !path.isEmpty && path != "/"
    }
    return true
}
