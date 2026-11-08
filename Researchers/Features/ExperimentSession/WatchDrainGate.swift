import Foundation

/// Identifies the exact child operations whose durable saves must precede a Watch close.
nonisolated struct WatchDrainGate: Equatable {
    enum Signal: Equatable {
        case voiceRecorded(session: UUID, record: UUID?)
        case voiceSaved(session: UUID, record: UUID, accepted: UUID?)
        case voiceFailed(session: UUID)
        case videoRecorded(session: UUID, record: UUID?)
        case videoSaved(session: UUID, record: UUID)
        case videoFailed(session: UUID)
        case videoSaveFailed(session: UUID, record: UUID)
        case photoSaved(UUID)
        case photoFailed(UUID)
    }

    enum Outcome: Equatable { case ignored, waiting, ready, failed }

    private(set) var voiceSession: UUID?
    private(set) var voiceRecord: UUID?
    private(set) var videoSession: UUID?
    private(set) var videoRecord: UUID?
    private(set) var photoRecord: UUID?

    init(
        voiceSession: UUID?, voiceRecord: UUID?, videoSession: UUID?,
        videoRecord: UUID?, photoRecord: UUID?
    ) {
        self.voiceSession = voiceSession
        self.voiceRecord = voiceRecord
        self.videoSession = videoSession
        self.videoRecord = videoRecord
        self.photoRecord = photoRecord
    }

    var isReady: Bool { voiceSession == nil && videoSession == nil && photoRecord == nil }

    static func canDrainVoice(isStarting: Bool, captureStartRequested: Bool) -> Bool {
        !isStarting || captureStartRequested
    }

    mutating func apply(_ signal: Signal) -> Outcome {
        switch signal {
        case let .voiceRecorded(session, record):
            return voiceRecorded(session: session, record: record)
        case let .voiceSaved(session, record, accepted):
            return voiceSaved(session: session, record: record, accepted: accepted)
        case let .voiceFailed(session):
            return voiceSession == session ? .failed : .ignored
        case let .videoRecorded(session, record):
            return videoRecorded(session: session, record: record)
        case let .videoSaved(session, record):
            return videoSaved(session: session, record: record)
        case let .videoFailed(session):
            return videoSession == session ? .failed : .ignored
        case let .videoSaveFailed(session, record):
            return videoSession == session && videoRecord == record ? .failed : .ignored
        case let .photoSaved(record):
            guard photoRecord == record else { return .ignored }
            photoRecord = nil
            return outcomeAfterSave
        case let .photoFailed(record):
            return photoRecord == record ? .failed : .ignored
        }
    }

    private var outcomeAfterSave: Outcome { isReady ? .ready : .waiting }

    private mutating func voiceRecorded(session: UUID, record: UUID?) -> Outcome {
        guard voiceSession == session else { return .ignored }
        guard let record else { return .failed }
        voiceRecord = record
        return outcomeAfterSave
    }

    private mutating func voiceSaved(session: UUID, record: UUID, accepted: UUID?) -> Outcome {
        guard voiceSession == session, voiceRecord == record, accepted == record else {
            return .ignored
        }
        voiceSession = nil
        voiceRecord = nil
        return outcomeAfterSave
    }

    private mutating func videoRecorded(session: UUID, record: UUID?) -> Outcome {
        guard videoSession == session else { return .ignored }
        guard let record else { return .failed }
        videoRecord = record
        return outcomeAfterSave
    }

    private mutating func videoSaved(session: UUID, record: UUID) -> Outcome {
        guard videoSession == session, videoRecord == record else { return .ignored }
        videoSession = nil
        videoRecord = nil
        return outcomeAfterSave
    }
}

/// A session exit can settle only the matching Watch close, never an unrelated record request.
nonisolated struct WatchCloseCompletionGate<SessionID: Equatable>: Equatable {
    enum Kind: Equatable { case pause, complete }

    let requestID: UUID
    let sessionID: SessionID
    let kind: Kind

    func matches(requestID: UUID?, sessionID: SessionID, kind: Kind) -> Bool {
        self.requestID == requestID && self.sessionID == sessionID && self.kind == kind
    }
}

/// Distinguishes separate asynchronous exits even when their session or request is the same.
nonisolated struct WatchCloseAttemptGate: Equatable {
    private(set) var activeID: UUID?
    private(set) var lastAcceptedID: UUID?

    mutating func begin(_ id: UUID) {
        activeID = id
        lastAcceptedID = nil
    }

    mutating func accept(_ id: UUID) -> Bool {
        guard activeID == id else { return false }
        activeID = nil
        lastAcceptedID = id
        return true
    }
}
