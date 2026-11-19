import ActivityKit
import ComposableArchitecture
import Foundation
import LabcordiOS
import LabcordShared
import UserNotifications

@MainActor
struct DebugAppDataReset {
    @Dependency(\.protocolAnalysisJobManager) private var jobManager

    func run() async throws -> String? {
        var cleanupFailures = try DebugExperimentStorage.reset()
        do {
            try await jobManager.resetDebugData()
        } catch {
            cleanupFailures.append("프로토콜 분석 파일")
        }
        SettingsReturnSessionStore.clear()
        UserDefaults.standard.removeObject(forKey: "lastExperimentNumber")

        let notifications = UNUserNotificationCenter.current()
        notifications.removeAllPendingNotificationRequests()
        notifications.removeAllDeliveredNotifications()
        for activity in Activity<TimerActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        guard !cleanupFailures.isEmpty else { return nil }
        let items = cleanupFailures.joined(separator: ", ")
        return "실험을 초기화했지만 일부 파일을 정리하지 못했어요. 다시 시도해 주세요. (\(items))"
    }
}
