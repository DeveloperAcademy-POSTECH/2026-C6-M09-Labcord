import Foundation

public struct WatchExperimentResponse: Codable, Equatable, Sendable {
    public enum Phase: String, Codable, Sendable {
        case received
        case processing
        case completed
        case failed
        case unknown
    }

    public let version: Int
    public let requestID: UUID
    public let phase: Phase
    public let experiments: [WatchExperimentSummary]?
    public let snapshot: WatchExperimentSnapshot?
    public let error: WatchExperimentError?
    public let startToken: UUID?
    public let record: WatchRecordSnapshot?
    public let queriedRequestID: UUID?

    public init(
        version: Int = WatchExperimentCommand.schemaVersion,
        requestID: UUID,
        phase: Phase,
        experiments: [WatchExperimentSummary]? = nil,
        snapshot: WatchExperimentSnapshot? = nil,
        error: WatchExperimentError? = nil,
        startToken: UUID? = nil,
        record: WatchRecordSnapshot? = nil,
        queriedRequestID: UUID? = nil
    ) {
        self.version = version
        self.requestID = requestID
        self.phase = phase
        self.experiments = experiments
        self.snapshot = snapshot
        self.error = error
        self.startToken = startToken
        self.record = record
        self.queriedRequestID = queriedRequestID
    }
}
