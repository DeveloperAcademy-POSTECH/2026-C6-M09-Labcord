import Foundation
import LabcordShared

public struct ExperimentSessionDetail: Equatable, Sendable {
    public let title: String
    public let timerSeconds: [Int]
    public let mode: ExperimentMode
    public let timers: [ExperimentTimer]
    public let speechContextualStrings: [String]

    public init(
        title: String,
        timerSeconds: [Int],
        mode: ExperimentMode,
        timers: [ExperimentTimer],
        speechContextualStrings: [String] = []
    ) {
        self.title = title
        self.timerSeconds = timerSeconds
        self.mode = mode
        self.timers = timers
        self.speechContextualStrings = speechContextualStrings
    }
}
