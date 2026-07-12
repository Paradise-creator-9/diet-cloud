import SwiftUI

@main
struct DietCloudApp: App {
    /// Built in App init; container construction must never throw or hang.
    @State private var container = AppDependencyContainer.makeDefault()

    var body: some Scene {
        WindowGroup {
            RootView(container: container)
                // Guaranteed non-empty chrome so a pure white screen always indicates a deeper bug.
                .background(Color(.systemBackground))
        }
    }
}
