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
                    status: timer.status == .running ? .running
                        : timer.status == .paused ? .paused : .finished,
                    measuredAt: date
                )
            },
            recordedAt: date,
            mode: detail.mode,
            phoneSessionActive: phoneSessionActive
        )
    }
}
