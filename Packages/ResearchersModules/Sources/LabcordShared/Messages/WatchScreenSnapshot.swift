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

    public init(
        destination: Destination, experimentID: UUID? = nil, stage: Stage? = nil,
        countdownEndsAt: Date? = nil, recording: WatchScreenRecording? = nil,
        revision: UInt64 = 0, recordedAt: Date = .now, timerDraftSeconds: Int? = nil
    ) {
        self.destination = destination
        self.experimentID = experimentID
        self.stage = stage
        self.timerDraftSeconds = timerDraftSeconds
        self.countdownEndsAt = countdownEndsAt
        self.recording = recording
        self.revision = revision
        self.recordedAt = recordedAt
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

    public func withRevision(_ revision: UInt64, recordedAt: Date = .now) -> Self {
        Self(
            destination: destination, experimentID: experimentID, stage: stage,
            countdownEndsAt: countdownEndsAt, recording: recording,
            revision: revision, recordedAt: recordedAt, timerDraftSeconds: timerDraftSeconds
        )
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
