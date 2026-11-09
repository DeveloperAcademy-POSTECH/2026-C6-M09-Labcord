import Foundation
import LabcordShared

public struct WatchExperimentState: Equatable, Sendable {
    public let experiment: WatchExperimentSummary
    public let detail: ExperimentSessionDetail

    public init(experiment: WatchExperimentSummary, detail: ExperimentSessionDetail) {
        self.experiment = experiment
        self.detail = detail
    }

    func snapshot(revision: UInt64, at date: Date) -> WatchExperimentSnapshot {
        WatchExperimentSnapshot(
            experiment: experiment,
            revision: revision,
            protocolTimerSeconds: detail.timerSeconds,
            timers: detail.timers.map { timer in
                WatchTimerSnapshot(
                    id: timer.id, durationSeconds: timer.durationSeconds,
                    remainingSeconds: timer.remainingSeconds(at: date),
                    status: watchTimerStatus(timer.status),
                    measuredAt: date
                )
            },
            recordedAt: date,
            mode: detail.mode
        )
    }
}

private func watchTimerStatus(_ status: ExperimentTimer.Status) -> WatchTimerSnapshot.Status {
    switch status {
    case .running: .running
    case .paused: .paused
    case .finished: .finished
    }
}
