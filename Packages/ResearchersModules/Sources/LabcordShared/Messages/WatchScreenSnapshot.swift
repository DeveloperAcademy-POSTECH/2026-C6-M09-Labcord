import Foundation

public struct WatchScreenSnapshot: Codable, Equatable, Sendable {
    public enum Destination: String, Codable, Sendable {
        case home
        case registration
        case experiment
        case result
    }

    public enum Stage: String, Codable, Sendable {
        case preparation
        case permission
        case countdown
        case active
        case pauseConfirmation
        case completionConfirmation
        case resumeConfirmation
        case paused
        case completed
        case timers
        case timerEditor
        case gestures
    }

    public let destination: Destination
    public let experimentID: UUID?
    public let stage: Stage?
    public let timerDraftSeconds: Int?
    public let countdownEndsAt: Date?
    public let recording: WatchScreenRecording?
    public let revision: UInt64
    public let recordedAt: Date
    public let epoch: WatchStateEpoch?
    public let gestureSession: WatchGestureSession?

    public init(
        destination: Destination, experimentID: UUID? = nil, stage: Stage? = nil,
        countdownEndsAt: Date? = nil, recording: WatchScreenRecording? = nil,
        revision: UInt64 = 0, recordedAt: Date = .now, timerDraftSeconds: Int? = nil,
        epoch: WatchStateEpoch? = nil, gestureSession: WatchGestureSession? = nil
    ) {
        self.destination = destination
        self.experimentID = experimentID
        self.stage = stage
        self.timerDraftSeconds = timerDraftSeconds
        self.countdownEndsAt = countdownEndsAt
        self.recording = recording
        self.revision = revision
        self.recordedAt = recordedAt
        self.epoch = epoch
        self.gestureSession = gestureSession
    }

    public var recordingExperimentID: UUID? {
        guard destination == .experiment,
              stage == .active || stage == .timers || stage == .timerEditor else { return nil }
        return experimentID
    }

    public var isValid: Bool {
        if let timerDraftSeconds {
            guard destination == .experiment, stage == .timerEditor,
                  (0..<86_400).contains(timerDraftSeconds) else { return false }
        }
        switch destination {
        case .home, .registration:
            return experimentID == nil && stage == nil && countdownEndsAt == nil
                && recording == nil
        case .experiment, .result:
            guard let experimentID else { return false }
            return recording.map { $0.experimentID == experimentID && $0.isValid } ?? true
        }
    }

    public func hasSameContent(as other: Self) -> Bool {
        destination == other.destination && experimentID == other.experimentID
            && stage == other.stage && countdownEndsAt == other.countdownEndsAt
            && recording == other.recording && timerDraftSeconds == other.timerDraftSeconds
    }

    public func matchesRevision(of current: Self) -> Bool {
        revision == current.revision && (epoch == nil || epoch == current.epoch)
    }

    public func withRevision(
        _ revision: UInt64, recordedAt: Date = .now, epoch: WatchStateEpoch? = nil,
        gestureSession: WatchGestureSession? = nil
    ) -> Self {
        Self(
            destination: destination, experimentID: experimentID, stage: stage,
            countdownEndsAt: countdownEndsAt, recording: recording,
            revision: revision, recordedAt: recordedAt, timerDraftSeconds: timerDraftSeconds,
            epoch: epoch ?? self.epoch, gestureSession: gestureSession ?? self.gestureSession
        )
    }
}

public struct WatchGestureSession: Codable, Equatable, Sendable {
    public let start: WatchStateVersion
    public let startedAt: Date

    public init(start: WatchStateVersion, startedAt: Date = .now) {
        self.start = start
        self.startedAt = startedAt
    }

    public func matches(_ screen: WatchScreenSnapshot?, experimentID: UUID) -> Bool {
        guard let screen, let session = screen.gestureSession else { return false }
        return screen.recordingExperimentID == experimentID && hasSameStart(as: session)
            && screen.epoch?.id == start.epoch.id && screen.revision >= start.revision
    }

    func hasSameStart(as other: Self) -> Bool {
        start.epoch.id == other.start.epoch.id && start.revision == other.start.revision
    }
}

public struct WatchScreenRecording: Codable, Equatable, Sendable {
    public enum Origin: String, Codable, Sendable {
        case phone
        case watch
    }

    public let id: UUID
    public let experimentID: UUID
    public let origin: Origin
    public let kind: WatchRecordSnapshot.Kind
    public let phase: WatchRecordSnapshot.Phase
    public let startedAt: Date?
    public let countdownEndsAt: Date?
    public let elapsedSeconds: TimeInterval?

    public init(
        id: UUID, experimentID: UUID, origin: Origin, kind: WatchRecordSnapshot.Kind,
        phase: WatchRecordSnapshot.Phase, startedAt: Date? = nil, countdownEndsAt: Date? = nil,
        elapsedSeconds: TimeInterval? = nil
    ) {
        self.id = id
        self.experimentID = experimentID
        self.origin = origin
        self.kind = kind
        self.phase = phase
        self.startedAt = startedAt
        self.countdownEndsAt = countdownEndsAt
        self.elapsedSeconds = elapsedSeconds
    }

    public var isValid: Bool {
        elapsedSeconds.map { $0.isFinite && $0 >= 0 } ?? true
    }
}
