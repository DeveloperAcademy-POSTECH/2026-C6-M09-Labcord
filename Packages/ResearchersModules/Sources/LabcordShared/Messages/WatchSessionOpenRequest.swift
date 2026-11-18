import Foundation

public struct WatchSessionOpenRequest: Codable, Sendable {
    public enum Action: String, Codable, Sendable {
        case open
        case cancel
        case leftExperiment
        case enteredExperiment
    }

    public nonisolated static let messageKey = "experiment.openSession.v1"

    public let requestID: UUID
    public let experimentID: UUID
    public let requestedAt: Date
    public let action: Action?

    public init(experimentID: UUID, action: Action = .open) {
        requestID = UUID()
        self.experimentID = experimentID
        requestedAt = .now
        self.action = action
    }
}
