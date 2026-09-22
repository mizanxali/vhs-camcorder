import SwiftUI

@main struct MyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            CamcorderView()
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    /// The app never auto-rotates. `CamcorderView` flips this between portrait and landscape from its button.
    static var orientationLock: UIInterfaceOrientationMask = .portrait

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.orientationLock
    }
}
