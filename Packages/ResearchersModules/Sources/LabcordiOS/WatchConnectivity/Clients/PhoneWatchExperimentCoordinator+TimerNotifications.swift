import ComposableArchitecture
import Foundation
import LabcordShared

extension PhoneWatchExperimentCoordinator {
    func reconcileJournalTimerNotifications() {
        guard let entries = journal?.entries.values else { return }
        var targets: Set<WatchTimerNotificationTarget> = []
        for entry in entries {
            guard let target = WatchTimerNotificationTarget(entry.command),
                  targets.insert(target).inserted else { continue }
            enqueueTimerNotificationSync(entry.command)
        }
    }

    @discardableResult
    func enqueueTimerNotificationSync(_ command: WatchExperimentCommand) -> Task<Void, Error>? {
        guard let target = WatchTimerNotificationTarget(command) else { return nil }
        let experimentID = target.experimentID
        let timerID = target.timerID
        let previous = timerNotificationTask
        let task = Task { @MainActor in
            _ = try? await previous?.value
            guard let state = try client.watchState(experimentID) else {
                throw WatchExperimentError.experimentNotFound
            }
            @Dependency(\.timerCompletionNotificationClient) var notifications
            @Dependency(\.notificationPermissionClient) var permission
            await notifications.cancelTimer(experimentID, timerID)
            let status = await permission.currentStatus()
            let timer = state.detail.timers.first { $0.id == timerID }
            guard WatchTimerNotificationTarget.shouldSchedule(
                timer, visible: visibleExperimentID == experimentID,
                authorized: [.authorized, .provisional, .ephemeral].contains(status), at: .now
            ), let timer else { return }
            try await notifications.schedule(experimentID, state.detail.title, timer)
            if visibleExperimentID == experimentID {
                await notifications.cancelTimer(experimentID, timerID)
            }
        }
        timerNotificationTask = task
        return task
    }
}
