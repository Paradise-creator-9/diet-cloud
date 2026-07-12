import SwiftUI

/// App shell: routes on auth phase. Stage 1 only — no diary features.
struct RootView: View {
    let container: AppDependencyContainer
    @State private var authViewModel: AuthViewModel

    init(container: AppDependencyContainer, authViewModel: AuthViewModel? = nil) {
        self.container = container
        _authViewModel = State(initialValue: authViewModel ?? container.makeAuthViewModel())
    }

    var body: some View {
        AuthRootView(viewModel: authViewModel)
            .task {
                await authViewModel.bootstrap()
            }
            .onOpenURL { url in
                Task { await authViewModel.handleOpenURL(url) }
            }
    }
}

#Preview("Signed out") {
    let config = AppConfig(
        supabaseURL: URL(string: "https://YOUR_PROJECT.supabase.co")!,
        supabaseAnonKey: "YOUR_SUPABASE_ANON_KEY",
        apiBaseURL: URL(string: "https://diet-cloud.vercel.app")!,
        storageBucket: "meal-photos",
        authRedirectURL: AppConfig.defaultAuthRedirectURL
    )
    let store = InMemoryCredentialStore()
    let container = AppDependencyContainer(config: config, credentialStore: store)
    RootView(container: container)
}
