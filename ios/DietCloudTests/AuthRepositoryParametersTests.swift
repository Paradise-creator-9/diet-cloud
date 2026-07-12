import XCTest
@testable import DietCloud

@MainActor
final class AuthRepositoryParametersTests: XCTestCase {
    func testMakeSendOTPParametersUsesConfiguredRedirect() async throws {
        let config = AppConfig(
            supabaseURL: URL(string: "https://abc.supabase.co")!,
            supabaseAnonKey: "anon-public-key",
            apiBaseURL: URL(string: "https://diet-cloud.vercel.app")!,
            storageBucket: "meal-photos",
            authRedirectURL: URL(string: "dietcloud://auth-callback")!
        )
        let provider = SupabaseClientProvider(config: config, credentialStore: InMemoryCredentialStore())
        let repo = AuthRepository(provider: provider)
        let params = try await repo.makeSendOTPParameters(email: "User@Example.com")
        XCTAssertEqual(params.email, "user@example.com")
        XCTAssertEqual(params.redirectTo.absoluteString, "dietcloud://auth-callback")
        XCTAssertNil(params.redirectTo.query)
    }

    func testMakeSendOTPParametersRejectsInvalidEmail() async {
        let config = AppConfig(
            supabaseURL: URL(string: "https://abc.supabase.co")!,
            supabaseAnonKey: "anon-public-key",
            apiBaseURL: URL(string: "https://diet-cloud.vercel.app")!,
            storageBucket: "meal-photos",
            authRedirectURL: AppConfig.defaultAuthRedirectURL
        )
        let provider = SupabaseClientProvider(config: config, credentialStore: InMemoryCredentialStore())
        let repo = AuthRepository(provider: provider)
        do {
            _ = try await repo.makeSendOTPParameters(email: "bad")
            XCTFail("Expected invalid email")
        } catch {
            XCTAssertEqual(error as? AppError, .auth(.invalidEmail))
        }
    }
}
