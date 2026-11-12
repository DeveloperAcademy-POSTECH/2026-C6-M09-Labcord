import UIKit

final class OrientationAppDelegate: NSObject, UIApplicationDelegate {
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
