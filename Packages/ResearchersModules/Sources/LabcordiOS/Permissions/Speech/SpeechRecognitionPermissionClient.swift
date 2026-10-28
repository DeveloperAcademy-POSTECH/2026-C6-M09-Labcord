import ComposableArchitecture
import LabcordShared
import Speech

public struct SpeechRecognitionPermissionClient: Sendable {
    public var currentStatus: @MainActor @Sendable () -> PermissionStatus
    public var requestAccess: @MainActor @Sendable () async -> PermissionStatus

    public init(
        currentStatus: @escaping @MainActor @Sendable () -> PermissionStatus,
        requestAccess: @escaping @MainActor @Sendable () async -> PermissionStatus
    ) {
        self.currentStatus = currentStatus
        self.requestAccess = requestAccess
    }
}

extension SpeechRecognitionPermissionClient: DependencyKey {
    public static let liveValue = SpeechRecognitionPermissionClient(
        currentStatus: { readStatus() },
        requestAccess: {
            if readStatus() == .notDetermined {
                await withCheckedContinuation { continuation in
                    SFSpeechRecognizer.requestAuthorization { _ in
                        continuation.resume()
                    }
                }
            }
            return readStatus()
        }
    )

    private static func readStatus() -> PermissionStatus {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .notDetermined:
            return .notDetermined
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .restricted
        }
    }
}

extension DependencyValues {
    public var speechRecognitionPermissionClient: SpeechRecognitionPermissionClient {
        get { self[SpeechRecognitionPermissionClient.self] }
        set { self[SpeechRecognitionPermissionClient.self] = newValue }
    }
}
