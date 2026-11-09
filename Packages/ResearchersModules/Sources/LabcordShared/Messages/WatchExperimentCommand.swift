import Foundation

public struct WatchExperimentCommand: Codable, Equatable, Sendable {
    public enum Operation: String, Codable, Sendable {
        case list
        case snapshot
        case prepareStart
        case start
        case pause
        case resume
        case complete
        case requestStatus
        case startTimer
        case pauseTimer
        case resumeTimer
        case deleteTimer
        case takePhoto
        case startVideo
        case stopVideo
        case confirmRecord
        case cancelRecord
    }

    public static let schemaVersion = 1
    public let version: Int
    public let requestID: UUID
    public let operation: Operation
    public let experimentID: UUID?
    public let expectedRevision: UInt64?
    public let targetID: UUID?
    public let durationSeconds: Int?
    public let startToken: UUID?

    public init(
        version: Int = Self.schemaVersion,
        requestID: UUID = UUID(),
        operation: Operation,
        experimentID: UUID? = nil,
        expectedRevision: UInt64? = nil,
        targetID: UUID? = nil,
        durationSeconds: Int? = nil,
        startToken: UUID? = nil
    ) {
        self.version = version
        self.requestID = requestID
        self.operation = operation
        self.experimentID = experimentID
        self.expectedRevision = expectedRevision
        self.targetID = targetID
        self.durationSeconds = durationSeconds
        self.startToken = startToken
    }
}

public enum WatchExperimentError: String, Codable, Error, Sendable {
    case notReachable
    case deliveryTimeout
    case unsupportedVersion
    case invalidPayload
    case experimentNotFound
    case invalidState
    case staleRevision
    case phoneBusy
    case phoneUnlockRequired
    case activeExperimentConflict
    case permissionDenied
    case cameraUnavailable
    case storageFailed
    case duplicateConflict
    case requestExpired
    case resultUnknown
}
