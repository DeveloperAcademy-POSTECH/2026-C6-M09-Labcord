import AVFAudio
import ComposableArchitecture

struct WatchMicrophonePermission: Sendable {
    var request: @Sendable () async -> Bool
}

extension WatchMicrophonePermission: DependencyKey {
    static let liveValue = Self {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}

extension DependencyValues {
    var watchMicrophonePermission: WatchMicrophonePermission {
        get { self[WatchMicrophonePermission.self] }
        set { self[WatchMicrophonePermission.self] = newValue }
    }
}
