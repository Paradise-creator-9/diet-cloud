import Foundation

/// Lightweight protocol-based DI root. Features depend on protocols, not
/// concrete Supabase SDK types beyond the repository boundary.
///
/// Not @MainActor: App property initializers must not require MainActor or
/// launch can fail before the first frame (white screen).
final class AppDependencyContainer: @unchecked Sendable {
    let config: AppConfig
    let supabase: SupabaseClientProviding
    let analyzeAPI: AnalyzeAPIClienting
    let diaryCalendar: DiaryCalendar
    let authRepository: AuthRepositoryProtocol
    let credentialStore: SecureCredentialStoring
    let sessionIdentity: SessionIdentityProviding
    let foodItemRepository: FoodItemRepositoryProtocol
    let bodyMetricsRepository: BodyMetricsRepositoryProtocol
    let dailyActivityRepository: DailyActivityRepositoryProtocol
    let exerciseActivityRepository: ExerciseActivityRepositoryProtocol
    let mealPhotoRepository: MealPhotoRepositoryProtocol

    init(
        config: AppConfig,
        credentialStore: SecureCredentialStoring = KeychainCredentialStore(),
        supabase: SupabaseClientProviding? = nil,
        analyzeAPI: AnalyzeAPIClienting? = nil,
        authRepository: AuthRepositoryProtocol? = nil,
        sessionIdentity: SessionIdentityProviding? = nil,
        foodItemRepository: FoodItemRepositoryProtocol? = nil,
        bodyMetricsRepository: BodyMetricsRepositoryProtocol? = nil,
        dailyActivityRepository: DailyActivityRepositoryProtocol? = nil,
        exerciseActivityRepository: ExerciseActivityRepositoryProtocol? = nil,
        mealPhotoRepository: MealPhotoRepositoryProtocol? = nil,
        diaryCalendar: DiaryCalendar = DiaryCalendar()
    ) {
        self.config = config
        self.credentialStore = credentialStore
        let provider = supabase ?? SupabaseClientProvider(config: config, credentialStore: credentialStore)
        self.supabase = provider
        self.analyzeAPI = analyzeAPI ?? AnalyzeAPIClient(provider: provider)
        self.authRepository = authRepository ?? AuthRepository(provider: provider)
        self.diaryCalendar = diaryCalendar

        let identity = sessionIdentity ?? SupabaseSessionIdentity(provider: provider)
        self.sessionIdentity = identity

        let photos = mealPhotoRepository ?? MealPhotoRepository(provider: provider, identity: identity)
        self.mealPhotoRepository = photos
        self.foodItemRepository = foodItemRepository
            ?? FoodItemRepository(provider: provider, identity: identity, photoRepository: photos)
        self.bodyMetricsRepository = bodyMetricsRepository
            ?? BodyMetricsRepository(provider: provider, identity: identity)
        self.dailyActivityRepository = dailyActivityRepository
            ?? DailyActivityRepository(provider: provider, identity: identity)
        self.exerciseActivityRepository = exerciseActivityRepository
            ?? ExerciseActivityRepository(provider: provider, identity: identity)
    }

    @MainActor
    func makeAuthViewModel() -> AuthViewModel {
        AuthViewModel(repository: authRepository, isConfigured: supabase.isConfigured)
    }

    @MainActor
    func makeTodayMealsViewModel(user: AuthUser) -> TodayMealsViewModel {
        TodayMealsViewModel(
            user: user,
            foodRepository: foodItemRepository,
            photoRepository: mealPhotoRepository,
            diaryCalendar: diaryCalendar
        )
    }

    /// Bootstrap from the main bundle; always returns a container (never throws).
    static func makeDefault() -> AppDependencyContainer {
        do {
            let config = try AppConfigLoader.loadFromBundle()
            return AppDependencyContainer(config: config)
        } catch {
            let fallback = AppConfig(
                supabaseURL: URL(string: "https://YOUR_PROJECT.supabase.co")!,
                supabaseAnonKey: "YOUR_SUPABASE_ANON_KEY",
                apiBaseURL: URL(string: "https://diet-cloud.vercel.app")!,
                storageBucket: "meal-photos",
                authRedirectURL: AppConfig.defaultAuthRedirectURL
            )
            return AppDependencyContainer(config: fallback)
        }
    }
}
