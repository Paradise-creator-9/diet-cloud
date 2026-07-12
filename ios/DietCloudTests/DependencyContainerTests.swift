import XCTest
@testable import DietCloud

@MainActor
final class DependencyContainerTests: XCTestCase {
    func testContainerWiresAnalyzeURLs() {
        let config = AppConfig(
            supabaseURL: URL(string: "https://abc.supabase.co")!,
            supabaseAnonKey: "anon-public-key",
            apiBaseURL: URL(string: "https://diet-cloud.vercel.app")!,
            storageBucket: "meal-photos",
            authRedirectURL: AppConfig.defaultAuthRedirectURL
        )
        let container = AppDependencyContainer(config: config, credentialStore: InMemoryCredentialStore())

        XCTAssertEqual(
            container.analyzeAPI.analyzeMealURL().absoluteString,
            "https://diet-cloud.vercel.app/api/analyze-meal"
        )
        XCTAssertEqual(
            container.analyzeAPI.analyzeBodyURL().absoluteString,
            "https://diet-cloud.vercel.app/api/analyze-body"
        )
        XCTAssertEqual(container.config.authRedirectURL.absoluteString, "dietcloud://auth-callback")
        XCTAssertTrue(container.supabase.isConfigured)
        XCTAssertNotNil(container.supabase.client)
        XCTAssertFalse(container.diaryCalendar.dateKey().isEmpty)
    }

    func testPlaceholderConfigNotNetworkReady() {
        let config = AppConfig(
            supabaseURL: URL(string: "https://YOUR_PROJECT.supabase.co")!,
            supabaseAnonKey: "YOUR_SUPABASE_ANON_KEY",
            apiBaseURL: URL(string: "https://diet-cloud.vercel.app")!,
            storageBucket: "meal-photos",
            authRedirectURL: AppConfig.defaultAuthRedirectURL
        )
        let container = AppDependencyContainer(config: config, credentialStore: InMemoryCredentialStore())
        XCTAssertFalse(container.supabase.isConfigured)
        XCTAssertNil(container.supabase.client)
    }
}
