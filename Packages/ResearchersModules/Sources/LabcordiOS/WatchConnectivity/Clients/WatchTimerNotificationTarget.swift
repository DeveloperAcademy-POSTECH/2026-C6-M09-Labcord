import Foundation
import LabcordShared

struct WatchTimerNotificationTarget: Hashable {
    let experimentID: UUID
    let timerID: UUID

    init?(_ command: WatchExperimentCommand) {
        guard let experimentID = command.experimentID else { return nil }
        let timerID: UUID
        switch command.operation {
        case .startTimer:
            timerID = command.requestID
        case .pauseTimer, .resumeTimer, .deleteTimer:
            guard let targetID = command.targetID else { return nil }
            timerID = targetID
        default:
            return nil
        }
        self.experimentID = experimentID
        self.timerID = timerID
    }

    static func shouldSchedule(
        _ timer: ExperimentTimer?, visible: Bool, authorized: Bool, at date: Date
    ) -> Bool {
        guard !visible, authorized, let timer else { return false }
        return timer.status == .running && timer.remainingSeconds(at: date) > 0
    }
}
