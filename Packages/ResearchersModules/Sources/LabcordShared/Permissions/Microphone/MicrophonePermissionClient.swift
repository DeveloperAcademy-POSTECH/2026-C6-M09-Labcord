import AVFoundation
import ComposableArchitecture

public struct MicrophonePermissionClient: Sendable {
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

extension MicrophonePermissionClient: DependencyKey {
    public static let liveValue = MicrophonePermissionClient(
        currentStatus: { readStatus() },
        requestAccess: {
            if readStatus() == .notDetermined {
                await AVAudioApplication.requestRecordPermission()
            }
            return readStatus()
        }
    )

    private static func readStatus() -> PermissionStatus {
        switch AVAudioApplication.shared.recordPermission {
        case .undetermined:
            return .notDetermined
        case .granted:
            return .authorized
        case .denied:
            return .denied
        @unknown default:
            return .restricted
        }
    }
}

extension DependencyValues {
    public var microphonePermissionClient: MicrophonePermissionClient {
        get { self[MicrophonePermissionClient.self] }
        set { self[MicrophonePermissionClient.self] = newValue }
    }
}
