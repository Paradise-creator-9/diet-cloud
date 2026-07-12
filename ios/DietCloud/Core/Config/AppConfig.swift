import Foundation

/// Public client configuration only.
/// Never load SERVICE_ROLE, GEMINI_API_KEY, or DIARY_INGEST_TOKEN into the app.
struct AppConfig: Equatable, Sendable {
    let supabaseURL: URL
    let supabaseAnonKey: String
    let apiBaseURL: URL
    let storageBucket: String

    /// Placeholder values from committed xcconfig — not a real project.
    var isPlaceholder: Bool {
        let urlHost = supabaseURL.host?.lowercased() ?? ""
        return urlHost.contains("your_project")
            || supabaseAnonKey.contains("YOUR_SUPABASE")
            || supabaseAnonKey == "placeholder-anon-key"
    }

    var isReadyForNetwork: Bool {
        !isPlaceholder
            && !supabaseAnonKey.isEmpty
            && !storageBucket.isEmpty
    }
}

enum AppConfigKey: String {
    case supabaseURL = "SUPABASE_URL"
    case supabaseAnonKey = "SUPABASE_ANON_KEY"
    case apiBaseURL = "API_BASE_URL"
    case storageBucket = "STORAGE_BUCKET"
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

        guard let supabaseURL = URL(string: supabaseURLString), supabaseURL.scheme != nil else {
            throw AppError.configuration(.invalidURL(key: AppConfigKey.supabaseURL.rawValue, value: supabaseURLString))
        }
        guard let apiBaseURL = URL(string: apiBaseURLString), apiBaseURL.scheme != nil else {
            throw AppError.configuration(.invalidURL(key: AppConfigKey.apiBaseURL.rawValue, value: apiBaseURLString))
        }
        guard !anonKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.configuration(.missingKey(AppConfigKey.supabaseAnonKey.rawValue))
        }
        guard !bucket.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AppError.configuration(.missingKey(AppConfigKey.storageBucket.rawValue))
        }

        return AppConfig(
            supabaseURL: supabaseURL,
            supabaseAnonKey: anonKey.trimmingCharacters(in: .whitespacesAndNewlines),
            apiBaseURL: apiBaseURL,
            storageBucket: bucket.trimmingCharacters(in: .whitespacesAndNewlines)
        )
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
}
