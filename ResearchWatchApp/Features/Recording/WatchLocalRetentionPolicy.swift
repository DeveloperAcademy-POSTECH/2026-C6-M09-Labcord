import LabcordShared

struct WatchLocalRetentionDisplay: Equatable {
    let originalRetained: Bool
    let captureCompleteConfirmed: Bool
}

enum WatchLocalRetentionPolicy {
    static func canRetry(
        isVoice: Bool, originalRetained: Bool, requiresSavedVerification: Bool
    ) -> Bool {
        originalRetained || (isVoice && requiresSavedVerification)
    }

    static func assess(
        _ retention: WatchAudioLocalRetention, recordingActive: Bool
    ) -> WatchLocalRetentionDisplay? {
        switch retention {
        case .none:
            return WatchLocalRetentionDisplay(
                originalRetained: false, captureCompleteConfirmed: false
            )
        case let .partial(chunkCount):
            return WatchLocalRetentionDisplay(
                originalRetained: chunkCount > 0, captureCompleteConfirmed: false
            )
        case let .complete(chunkCount):
            return WatchLocalRetentionDisplay(
                originalRetained: chunkCount > 0,
                captureCompleteConfirmed: chunkCount > 0 && !recordingActive
            )
        case .damaged:
            return nil
        }
    }
}
