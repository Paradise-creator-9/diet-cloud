import Foundation

/// Lightweight protocol-based DI root. Features depend on protocols, not
/// concrete Supabase SDK types beyond the repository boundary.
@MainActor
final class AppDependencyContainer {
    let config: AppConfig
    let supabase: SupabaseClientProviding
    let analyzeAPI: AnalyzeAPIClienting
    let diaryCalendar: DiaryCalendar
    let authRepository: AuthRepositoryProtocol
    let credentialStore: SecureCredentialStoring

    init(
        config: AppConfig,
        credentialStore: SecureCredentialStoring = KeychainCredentialStore(),
        supabase: SupabaseClientProviding? = nil,
        analyzeAPI: AnalyzeAPIClienting? = nil,
        authRepository: AuthRepositoryProtocol? = nil,
        diaryCalendar: DiaryCalendar = DiaryCalendar()
    ) {
        self.config = config
        self.credentialStore = credentialStore
        let provider = supabase ?? SupabaseClientProvider(config: config, credentialStore: credentialStore)
        self.supabase = provider
        self.analyzeAPI = analyzeAPI ?? AnalyzeAPIClient(provider: provider)
        self.authRepository = authRepository ?? AuthRepository(provider: provider)
        self.diaryCalendar = diaryCalendar
    }

    func makeAuthViewModel() -> AuthViewModel {
        AuthViewModel(repository: authRepository, isConfigured: supabase.isConfigured)
    }

    /// Bootstrap from the main bundle; falls back to a non-crashing placeholder
    /// only if Info.plist is broken (should not happen in a correct build).
    static func makeDefault() -> AppDependencyContainer {
        do {
            let config = try AppConfigLoader.loadFromBundle()
            return AppDependencyContainer(config: config)
        } catch {
            let fallback = AppConfig(
                supabaseURL: URL(string: "https://YOUR_PROJECT.supabase.co")!,
                supabaseAnonKey: "YOUR_SUPABASE_ANON_KEY",
                apiBaseURL: URL(string: "https://diet-cloud.vercel.app")!,
                storageBucket: "meal-photos"
            )
            return AppDependencyContainer(config: fallback)
        }
    }
}
