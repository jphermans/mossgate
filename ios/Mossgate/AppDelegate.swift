import UIKit

/// Locks the app to portrait during the splash, then unlocks into landscape
/// once the game starts. Set via `RootView.onChange(of: phase)`.
final class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock: UIInterfaceOrientationMask = .portrait

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        AppDelegate.orientationLock
    }
}