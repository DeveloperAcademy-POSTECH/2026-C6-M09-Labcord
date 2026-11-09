import ComposableArchitecture
import Foundation
import LabcordShared
import UserNotifications

public struct TimerCompletionNotificationClient: Sendable {
    public var schedule: @MainActor @Sendable (UUID, String, ExperimentTimer) async throws -> Void
    public var cancelTimer: @MainActor @Sendable (UUID, UUID) async -> Void
    public var cancelForExperiment: @MainActor @Sendable (UUID) async -> Void

    public init(
        schedule: @escaping @MainActor @Sendable (
            UUID, String, ExperimentTimer
        ) async throws -> Void,
        cancelForExperiment: @escaping @MainActor @Sendable (UUID) async -> Void,
        cancelTimer: @escaping @MainActor @Sendable (UUID, UUID) async -> Void
    ) {
        self.schedule = schedule
        self.cancelForExperiment = cancelForExperiment
        self.cancelTimer = cancelTimer
    }
}

extension TimerCompletionNotificationClient: DependencyKey {
    public static let liveValue = TimerCompletionNotificationClient(
        schedule: { experimentID, title, timer in
            let pausedDuration = timer.pauseIntervals.reduce(0.0) { total, interval in
                total + max(
                    0,
                    (interval.resumedAt ?? interval.pausedAt).timeIntervalSince(interval.pausedAt)
                )
            }
            let endsAt = timer.startedAt.addingTimeInterval(
                TimeInterval(timer.durationSeconds) + pausedDuration
            )
            let content = UNMutableNotificationContent()
            let timerName = timerLabel(for: timer.durationSeconds)
            content.body = "\(title)에서 \(timerName)가 종료되었습니다."
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: notificationID(experimentID: experimentID, timerID: timer.id),
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(
                    timeInterval: max(1, endsAt.timeIntervalSinceNow),
                    repeats: false
                )
            )
            try await UNUserNotificationCenter.current().add(request)
        },
        cancelForExperiment: { experimentID in
            let center = UNUserNotificationCenter.current()
            let prefix = "timer-completion-\(experimentID.uuidString)-"
            let requests = await center.pendingNotificationRequests()
            let identifiers = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
        },
        cancelTimer: { experimentID, timerID in
            UNUserNotificationCenter.current().removePendingNotificationRequests(
                withIdentifiers: [notificationID(experimentID: experimentID, timerID: timerID)]
            )
        }
    )

    private static func notificationID(experimentID: UUID, timerID: UUID) -> String {
        "timer-completion-\(experimentID.uuidString)-\(timerID.uuidString)"
    }

    private static func timerLabel(for seconds: Int) -> String {
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainingSeconds = seconds % 60
        let parts = [
            hours > 0 ? "\(hours)시간" : nil,
            minutes > 0 ? "\(minutes)분" : nil,
            remainingSeconds > 0 ? "\(remainingSeconds)초" : nil
        ].compactMap { $0 }
        return "\(parts.joined()) 타이머"
    }
}

extension DependencyValues {
    public var timerCompletionNotificationClient: TimerCompletionNotificationClient {
        get { self[TimerCompletionNotificationClient.self] }
        set { self[TimerCompletionNotificationClient.self] = newValue }
    }
}
