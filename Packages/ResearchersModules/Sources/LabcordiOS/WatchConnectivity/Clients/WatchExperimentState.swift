import Foundation
import LabcordShared

public struct WatchExperimentState: Equatable, Sendable {
    public let experiment: WatchExperimentSummary
    public let detail: ExperimentSessionDetail

    public init(experiment: WatchExperimentSummary, detail: ExperimentSessionDetail) {
        self.experiment = experiment
        self.detail = detail
    }

    func snapshot(
        revision: UInt64, at date: Date, phoneSessionActive: Bool? = nil
    ) -> WatchExperimentSnapshot {
        WatchExperimentSnapshot(
            experiment: experiment,
            revision: revision,
            protocolTimerSeconds: detail.timerSeconds,
            timers: detail.timers.map { timer in
                WatchTimerSnapshot(
                    id: timer.id, durationSeconds: timer.durationSeconds,
                    remainingSeconds: timer.remainingSeconds(at: date),
                    status: watchTimerStatus(timer.status),
                    measuredAt: timerMeasurementDate(timer, at: date)
                )
            },
            recordedAt: date,
            mode: detail.mode, phoneSessionActive: phoneSessionActive
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

private func timerMeasurementDate(_ timer: ExperimentTimer, at date: Date) -> Date {
    guard timer.status == .running else { return date }
    let pauseDuration = timer.pauseIntervals.reduce(0.0) { total, pause in
        total + max(0, (pause.resumedAt ?? pause.pausedAt).timeIntervalSince(pause.pausedAt))
    }
    let end = timer.startedAt.addingTimeInterval(Double(timer.durationSeconds) + pauseDuration)
    return end.addingTimeInterval(-Double(timer.remainingSeconds(at: date)))
}
