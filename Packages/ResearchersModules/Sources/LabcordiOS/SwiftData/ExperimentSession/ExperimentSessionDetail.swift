import Foundation
import LabcordShared

public struct ExperimentSessionDetail: Equatable, Sendable {
    public let title: String
    public let timerSeconds: [Int]
    public let mode: ExperimentMode
    public let timers: [ExperimentTimer]

    public init(
        title: String,
        timerSeconds: [Int],
        mode: ExperimentMode,
        timers: [ExperimentTimer]
    ) {
        self.title = title
        self.timerSeconds = timerSeconds
        self.mode = mode
        self.timers = timers
    }
}
