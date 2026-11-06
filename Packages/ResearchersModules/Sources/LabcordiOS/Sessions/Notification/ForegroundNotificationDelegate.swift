import Foundation
import UserNotifications

public final class ForegroundNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    public var onTimerCompletionTap: ((UUID) -> Void)?
    private var pendingExperimentID: UUID?

    public override init() {
        super.init()
    }

    public func takePendingExperimentID() -> UUID? {
        defer { pendingExperimentID = nil }
        return pendingExperimentID
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let identifier = response.notification.request.identifier
        let prefix = "timer-completion-"
        guard identifier.hasPrefix(prefix),
              let experimentID = UUID(uuidString: String(
                  identifier.dropFirst(prefix.count).prefix(36)
              )) else { return }

        await MainActor.run {
            if let onTimerCompletionTap {
                onTimerCompletionTap(experimentID)
            } else {
                pendingExperimentID = experimentID
            }
        }
    }
}
