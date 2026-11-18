import UIKit
import UserNotifications

final class OrientationAppDelegate: NSObject, UIApplicationDelegate,
    UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        SessionOrientation.supportedOrientations
    }
}

enum SessionOrientation {
    private(set) static var supportedOrientations: UIInterfaceOrientationMask = .portrait

    static func toggle() {
        set(supportedOrientations == .portrait ? .landscapeRight : .portrait)
    }

    static func reset() {
        set(.portrait)
    }

    private static func set(_ orientation: UIInterfaceOrientationMask) {
        supportedOrientations = orientation

        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientation))
        }
    }
}
