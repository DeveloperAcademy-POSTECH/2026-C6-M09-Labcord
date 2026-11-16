import Foundation

public struct WatchSessionOpenRequest: Codable, Sendable {
    public nonisolated static let messageKey = "experiment.openSession.v1"

    public let requestID: UUID
    public let experimentID: UUID
    public let requestedAt: Date

    public init(experimentID: UUID) {
        requestID = UUID()
        self.experimentID = experimentID
        requestedAt = .now
    }
}
