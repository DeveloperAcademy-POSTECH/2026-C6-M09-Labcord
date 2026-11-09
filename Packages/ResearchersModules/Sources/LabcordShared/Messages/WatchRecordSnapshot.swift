import Foundation

public struct WatchRecordSnapshot: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case photo
        case video
        case audio
    }

    public enum Phase: String, Codable, Sendable {
        case capturing
        case recording
        case previewing
        case review
        case saving
        case saved
        case failed
        case cancelled
    }

    public let experimentID: UUID?
    public let revision: UInt64?
    public let transcript: String?
    public let isFinalTranscript: Bool?
    public let originalRetained: Bool?
    public let error: WatchExperimentError?
    public let id: UUID
    public let kind: Kind
    public let phase: Phase
    public let startedAt: Date?
    public let canAutoSave: Bool?

    public init(
        id: UUID, kind: Kind, phase: Phase, startedAt: Date? = nil, canAutoSave: Bool? = nil,
        experimentID: UUID? = nil, revision: UInt64? = nil, transcript: String? = nil,
        isFinalTranscript: Bool? = nil, originalRetained: Bool? = nil,
        error: WatchExperimentError? = nil
    ) {
        self.experimentID = experimentID
        self.revision = revision
        self.transcript = transcript
        self.isFinalTranscript = isFinalTranscript
        self.originalRetained = originalRetained
        self.error = error
        self.id = id
        self.kind = kind
        self.phase = phase
        self.startedAt = startedAt
        self.canAutoSave = canAutoSave
    }

    public func withContext(experimentID: UUID, revision: UInt64?) -> Self {
        Self(
            id: id, kind: kind, phase: phase, startedAt: startedAt, canAutoSave: canAutoSave,
            experimentID: experimentID, revision: revision, transcript: transcript,
            isFinalTranscript: isFinalTranscript, originalRetained: originalRetained, error: error
        )
    }
}
