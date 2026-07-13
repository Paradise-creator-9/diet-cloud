import SwiftUI
import UIKit

/// UIKit app delegate: install notification center delegate before first frame.
final class DietCloudAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        AppNotificationDelegate.shared.install()
        return true
    }
}

@main
struct DietCloudApp: App {
    @UIApplicationDelegateAdaptor(DietCloudAppDelegate.self) private var appDelegate
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
