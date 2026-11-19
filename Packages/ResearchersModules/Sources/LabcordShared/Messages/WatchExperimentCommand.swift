import Foundation

public struct WatchExperimentCommand: Codable, Equatable, Sendable {
    public enum Operation: String, Codable, Sendable {
        case list
        case screen
        case navigate
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
    public let timerStartedAt: Date?
    public let timerPauseIntervals: [ExperimentTimer.PauseInterval]?
    public let startToken: UUID?
    public let screen: WatchScreenSnapshot?
    public let discardTimerDraft: Bool?
    public let recordKind: WatchRecordSnapshot.Kind?
    public let expectedEpoch: WatchStateEpoch?

    public init(
        version: Int = Self.schemaVersion,
        requestID: UUID = UUID(),
        operation: Operation,
        experimentID: UUID? = nil,
        expectedRevision: UInt64? = nil,
        targetID: UUID? = nil,
        durationSeconds: Int? = nil,
        timerStartedAt: Date? = nil,
        timerPauseIntervals: [ExperimentTimer.PauseInterval]? = nil,
        startToken: UUID? = nil,
        screen: WatchScreenSnapshot? = nil,
        discardTimerDraft: Bool? = nil,
        recordKind: WatchRecordSnapshot.Kind? = nil,
        expectedEpoch: WatchStateEpoch? = nil
    ) {
        self.version = version
        self.requestID = requestID
        self.operation = operation
        self.experimentID = experimentID
        self.expectedRevision = expectedRevision
        self.targetID = targetID
        self.durationSeconds = durationSeconds
        self.timerStartedAt = timerStartedAt
        self.timerPauseIntervals = timerPauseIntervals
        self.startToken = startToken
        self.screen = screen
        self.discardTimerDraft = discardTimerDraft
        self.recordKind = recordKind
        self.expectedEpoch = expectedEpoch
    }

    public var isCameraCommand: Bool {
        switch operation {
        case .takePhoto, .startVideo, .stopVideo: true
        case .confirmRecord, .cancelRecord: recordKind != .audio
        default: false
        }
    }

    public func canInterruptCameraCommand(_ active: Self) -> Bool {
        guard requestID != active.requestID, let experimentID,
              experimentID == active.experimentID,
              let targetID, targetID == (active.targetID ?? active.requestID) else {
            return false
        }
        switch (active.operation, operation) {
        case (.takePhoto, .cancelRecord): return recordKind == nil || recordKind == .photo
        case (.startVideo, .stopVideo): return recordKind == nil || recordKind == .video
        default: return false
        }
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
