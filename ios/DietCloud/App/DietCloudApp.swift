import SwiftUI

@main
struct DietCloudApp: App {
    private let container = AppDependencyContainer.makeDefault()

    var body: some Scene {
        WindowGroup {
            RootView(container: container)
        }
    }
}
