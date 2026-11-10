import Foundation
import LabcordShared

struct WatchRecordPresentation: Equatable, Identifiable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case voice
        case photo
        case video
    }

    enum Phase: Equatable, Sendable {
        case starting
        case capturing
        case stopping
        case transferring
        case transcribing
        case review
        case saving
        case saved
        case failed
        case cancelled
    }

    let id: UUID
    let experimentID: UUID
    let kind: Kind
    var revision: UInt64 = 0
    var phase: Phase = .starting
    var startedAt: Date?
    var elapsedSeconds = 0
    var transcript = ""
    var isFinalTranscript = false
    var hasTranscriptConflict = false
    var originalRetained = false
    var requiresSavedVerification = false
    var captureCompleteConfirmed = false
    var captureRejectedBeforeStart = false
    var detail: String?

    var canAutoSave = false

    var canRecapture: Bool {
        phase == .failed && captureRejectedBeforeStart && !originalRetained
    }

    var isSettled: Bool { phase == .saved || phase == .cancelled || canRecapture }

    var isRecoverableVoiceFailure: Bool {
        kind == .voice && phase == .failed && originalRetained && captureCompleteConfirmed
    }

    static func isEmptyVoiceCapture(
        local: WatchAudioReceipt, remote: WatchAudioReceipt?, hasActiveCapture: Bool
    ) -> Bool {
        guard !hasActiveCapture, local.receivedSequences.isEmpty, local.manifest == nil,
              local.savedRecordID == nil, !local.isCancelled else { return false }
        guard let remote else { return true }
        return remote.receivedSequences.isEmpty && remote.manifest == nil
            && remote.savedRecordID == nil && !remote.isReviewing
            && !remote.isCancelled && remote.failure == nil
    }

    func photoCountdownRemaining(at date: Date) -> Int? {
        guard kind == .photo, phase == .starting, let startedAt else { return nil }
        let remaining = max(0, min(5, 5 - date.timeIntervalSince(startedAt)))
        return Int(ceil(remaining))
    }
}

struct WatchRecordingUIBridge: Sendable {
    enum Input: Equatable, Sendable {
        case startVoice(experimentID: UUID, recordID: UUID)
        case startRemoteVoice(experimentID: UUID, recordID: UUID, expiresAt: Date)
        case stopVoice(experimentID: UUID, recordID: UUID)
        case retry(experimentID: UUID, recordID: UUID)
        case reconcile
        case stopForExperiment(UUID)
        case cancelActiveVoiceForPause(experimentID: UUID, recordID: UUID?)
    }

    var perform: @Sendable (Input) async throws -> Void
    var updates: @Sendable () async -> AsyncStream<WatchRecordPresentation>
}

extension WatchRecordPresentation {
    init(snapshot: WatchRecordSnapshot, experimentID: UUID, revision: UInt64) {
        let kind: Kind = switch snapshot.kind {
        case .photo: .photo
        case .video: .video
        case .audio: .voice
        }
        self.init(id: snapshot.id, experimentID: experimentID, kind: kind)
        self.revision = revision
        startedAt = snapshot.startedAt
        transcript = snapshot.transcript ?? ""
        isFinalTranscript = snapshot.isFinalTranscript ?? false
        canAutoSave = snapshot.phase == .review && snapshot.canAutoSave == true
        originalRetained = snapshot.originalRetained ?? (snapshot.phase == .saved)
        phase = Self.displayPhase(snapshot.phase)
        if snapshot.phase == .capturing, snapshot.kind == .photo { phase = .starting }
        if snapshot.phase == .previewing {
            detail = "iPhone에서 영상 미리보기가 끝나면 저장을 확인할 수 있어요."
        }
        if snapshot.phase == .saved, snapshot.kind == .audio {
            phase = .saving
            originalRetained = false
            requiresSavedVerification = true
            detail = "최종 저장 확인과 보관 원본을 대조하고 있어요."
        }
        if snapshot.phase == .failed {
            captureRejectedBeforeStart = snapshot.kind != .audio && snapshot.startedAt == nil
                && (snapshot.error == .cameraUnavailable || snapshot.error == .permissionDenied)
                && !originalRetained
        }
        if let error = snapshot.error { detail = error.watchMessage }
    }

    private static func displayPhase(_ phase: WatchRecordSnapshot.Phase) -> Phase {
        switch phase {
        case .capturing, .recording: .capturing
        case .previewing: .stopping
        case .review: .review
        case .saving: .saving
        case .saved: .saved
        case .failed: .failed
        case .cancelled: .cancelled
        }
    }
}
