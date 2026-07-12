import XCTest
@testable import DietCloud

@MainActor
final class LaunchUISmokeTests: XCTestCase {
    func testBootstrapWithoutConfigShowsSignedOutNotLoading() async {
        let repo = MockAuthRepository()
        let vm = AuthViewModel(repository: repo, isConfigured: false)
        XCTAssertEqual(vm.phase, .loading)
        await vm.bootstrap()
        XCTAssertEqual(vm.phase, .signedOut)
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertFalse(vm.errorMessage!.isEmpty)
    }

    func testBootstrapWithConfigAndNoSessionShowsLogin() async {
        let repo = MockAuthRepository()
        let vm = AuthViewModel(repository: repo, isConfigured: true)
        await vm.bootstrap()
        XCTAssertEqual(vm.phase, .signedOut)
        XCTAssertNotNil(vm.statusMessage)
    }

    func testRootViewInitialPhaseIsLoadingUntilBootstrap() {
        let config = AppConfig(
            supabaseURL: URL(string: "https://abc.supabase.co")!,
            supabaseAnonKey: "anon-public-key",
            apiBaseURL: URL(string: "https://diet-cloud.vercel.app")!,
            storageBucket: "meal-photos",
            authRedirectURL: AppConfig.defaultAuthRedirectURL
        )
        let container = AppDependencyContainer(config: config, credentialStore: InMemoryCredentialStore())
        let vm = AuthViewModel(repository: MockAuthRepository(), isConfigured: true)
        XCTAssertEqual(vm.phase, .loading)
        // Constructing RootView must not crash (smoke).
        _ = RootView(container: container, authViewModel: vm)
        XCTAssertFalse(container.config.safeDiagnostics.isEmpty)
    }
}
