import Foundation
import LabcordShared

public struct ExperimentSessionDetail: Equatable, Sendable {
    public let title: String
    public let timerSeconds: [Int]
    public let mode: ExperimentMode
    public let timers: [ExperimentTimer]

    public let speechTerms: [String]
    public let speechUnits: [String]
    public let speechContextualStrings: [String]
    public let speechPhoneticReplacements: [String: String]

    public init(
        title: String,
        timerSeconds: [Int],
        mode: ExperimentMode,
        timers: [ExperimentTimer],
        speechTerms: [String] = [],
        speechUnits: [String] = [],
        speechContextualStrings: [String] = [],
        speechPhoneticReplacements: [String: String] = [:]
    ) {
        self.title = title
        self.timerSeconds = timerSeconds
        self.mode = mode
        self.timers = timers
        self.speechTerms = speechTerms
        self.speechUnits = speechUnits
        self.speechContextualStrings = speechContextualStrings
        self.speechPhoneticReplacements = speechPhoneticReplacements
    }
}
