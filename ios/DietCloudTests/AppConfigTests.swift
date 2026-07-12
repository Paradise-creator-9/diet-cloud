import XCTest
@testable import DietCloud

final class AppConfigTests: XCTestCase {
    func testLoadValidDictionary() throws {
        let config = try AppConfigLoader.load(from: [
            "SUPABASE_URL": "https://abc.supabase.co",
            "SUPABASE_ANON_KEY": "anon-public-key",
            "API_BASE_URL": "https://diet-cloud.vercel.app",
            "STORAGE_BUCKET": "meal-photos",
            "DIETCLOUD_AUTH_REDIRECT_URL": "dietcloud://auth-callback",
        ])

        XCTAssertEqual(config.supabaseURL.host, "abc.supabase.co")
        XCTAssertEqual(config.supabaseAnonKey, "anon-public-key")
        XCTAssertEqual(config.apiBaseURL.host, "diet-cloud.vercel.app")
        XCTAssertEqual(config.storageBucket, "meal-photos")
        XCTAssertEqual(config.authRedirectURL.absoluteString, "dietcloud://auth-callback")
        XCTAssertTrue(config.isReadyForNetwork)
        XCTAssertFalse(config.isPlaceholder)
    }

    func testMissingRedirectURLUsesSafeDefault() throws {
        let config = try AppConfigLoader.load(from: [
            "SUPABASE_URL": "https://abc.supabase.co",
            "SUPABASE_ANON_KEY": "anon-public-key",
            "API_BASE_URL": "https://diet-cloud.vercel.app",
            "STORAGE_BUCKET": "meal-photos",
        ])
        XCTAssertEqual(config.authRedirectURL, AppConfig.defaultAuthRedirectURL)
        XCTAssertEqual(config.authRedirectURL.absoluteString, "dietcloud://auth-callback")
    }

    func testRedirectURLWithTokenQueryIsRejected() {
        XCTAssertThrowsError(
            try AppConfigLoader.load(from: [
                "SUPABASE_URL": "https://abc.supabase.co",
                "SUPABASE_ANON_KEY": "anon-public-key",
                "API_BASE_URL": "https://diet-cloud.vercel.app",
                "STORAGE_BUCKET": "meal-photos",
                "DIETCLOUD_AUTH_REDIRECT_URL": "dietcloud://auth-callback?access_token=secret",
            ])
        ) { error in
            guard let appError = error as? AppError else {
                return XCTFail("Expected AppError")
            }
            XCTAssertEqual(appError.code, "configuration")
            XCTAssertFalse(appError.userMessage.contains("secret"))
            XCTAssertFalse(appError.userMessage.contains("access_token="))
        }
    }

    func testPlaceholderDetection() throws {
        let config = try AppConfigLoader.load(from: [
            "SUPABASE_URL": "https://YOUR_PROJECT.supabase.co",
            "SUPABASE_ANON_KEY": "YOUR_SUPABASE_ANON_KEY",
            "API_BASE_URL": "https://diet-cloud.vercel.app",
            "STORAGE_BUCKET": "meal-photos",
        ])

        XCTAssertTrue(config.isPlaceholder)
        XCTAssertFalse(config.isReadyForNetwork)
        XCTAssertEqual(config.authRedirectURL, AppConfig.defaultAuthRedirectURL)
    }

    func testMissingKeyThrows() {
        XCTAssertThrowsError(
            try AppConfigLoader.load(from: [
                "SUPABASE_URL": "https://abc.supabase.co",
                "API_BASE_URL": "https://diet-cloud.vercel.app",
                "STORAGE_BUCKET": "meal-photos",
            ])
        ) { error in
            guard let appError = error as? AppError else {
                return XCTFail("Expected AppError")
            }
            XCTAssertEqual(appError.code, "configuration")
            if case .configuration(.missingKey(let key)) = appError {
                XCTAssertEqual(key, "SUPABASE_ANON_KEY")
            } else {
                XCTFail("Expected missingKey")
            }
        }
    }

    func testInvalidURLThrows() {
        XCTAssertThrowsError(
            try AppConfigLoader.load(from: [
                "SUPABASE_URL": "not a url",
                "SUPABASE_ANON_KEY": "anon",
                "API_BASE_URL": "https://diet-cloud.vercel.app",
                "STORAGE_BUCKET": "meal-photos",
            ])
        ) { error in
            guard let appError = error as? AppError else {
                return XCTFail("Expected AppError")
            }
            if case .configuration(.invalidURL(let key, _)) = appError {
                XCTAssertEqual(key, "SUPABASE_URL")
            } else {
                XCTFail("Expected invalidURL, got \(appError)")
            }
        }
    }

    /// Regression: xcconfig `//` comments truncated URLs to `https:` → launch white screen.
    func testTruncatedHTTPSURLIsRejected() {
        XCTAssertThrowsError(
            try AppConfigLoader.load(from: [
                "SUPABASE_URL": "https:",
                "SUPABASE_ANON_KEY": "anon-public-key",
                "API_BASE_URL": "https://diet-cloud.vercel.app",
                "STORAGE_BUCKET": "meal-photos",
                "DIETCLOUD_AUTH_REDIRECT_URL": "dietcloud://auth-callback",
            ])
        ) { error in
            guard let appError = error as? AppError else {
                return XCTFail("Expected AppError")
            }
            XCTAssertEqual(appError.code, "configuration")
            // Must not echo long secrets
            XCTAssertFalse(appError.userMessage.contains("anon-public-key"))
        }
    }

    func testTruncatedDietCloudRedirectIsRejected() {
        XCTAssertThrowsError(
            try AppConfigLoader.resolveAuthRedirectURL(from: [
                "DIETCLOUD_AUTH_REDIRECT_URL": "dietcloud:",
            ])
        )
    }

    func testPlaceholderWhenHostMissingIsNotNetworkReady() {
        // Constructed only if loader is bypassed; still must not look "ready".
        let config = AppConfig(
            supabaseURL: URL(string: "https://example.invalid")!,
            supabaseAnonKey: "YOUR_SUPABASE_ANON_KEY",
            apiBaseURL: URL(string: "https://diet-cloud.vercel.app")!,
            storageBucket: "meal-photos",
            authRedirectURL: AppConfig.defaultAuthRedirectURL
        )
        XCTAssertTrue(config.isPlaceholder)
        XCTAssertFalse(config.isReadyForNetwork)
        XCTAssertFalse(config.safeDiagnostics.contains("YOUR_SUPABASE"))
    }

    func testExampleConfigValuesAreNotSecrets() {
        // Guard that committed examples never look like JWTs or service keys.
        let exampleRedirect = "dietcloud://auth-callback"
        XCTAssertFalse(exampleRedirect.contains("eyJ"))
        XCTAssertFalse(exampleRedirect.contains("service_role"))
        XCTAssertEqual(AppConfig.defaultAuthRedirectURL.absoluteString, exampleRedirect)
    }
}
