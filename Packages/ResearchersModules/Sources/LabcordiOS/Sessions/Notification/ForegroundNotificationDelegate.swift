import Foundation
import UserNotifications

public final class ForegroundNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    public override init() {
        super.init()
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
