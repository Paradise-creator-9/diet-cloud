import Foundation

/// Lightweight protocol-based DI root. Features depend on protocols, not
/// concrete Supabase SDK types.
@MainActor
final class AppDependencyContainer {
    let config: AppConfig
    let supabase: SupabaseClientProviding
    let analyzeAPI: AnalyzeAPIClienting
    let diaryCalendar: DiaryCalendar

    init(
        config: AppConfig,
        supabase: SupabaseClientProviding? = nil,
        analyzeAPI: AnalyzeAPIClienting? = nil,
        diaryCalendar: DiaryCalendar = DiaryCalendar()
    ) {
        self.config = config
        let provider = supabase ?? SupabaseClientProvider(config: config)
        self.supabase = provider
        self.analyzeAPI = analyzeAPI ?? AnalyzeAPIClient(provider: provider)
        self.diaryCalendar = diaryCalendar
    }

    /// Bootstrap from the main bundle; falls back to a non-crashing placeholder
    /// only if Info.plist is broken (should not happen in a correct build).
    static func makeDefault() -> AppDependencyContainer {
        do {
            let config = try AppConfigLoader.loadFromBundle()
            return AppDependencyContainer(config: config)
        } catch {
            // Keep the process alive so UI can show configuration diagnostics.
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
