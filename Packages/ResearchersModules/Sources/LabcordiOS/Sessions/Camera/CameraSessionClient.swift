import ComposableArchitecture
import Foundation

public enum CameraHandEvent: Equatable, Sendable {
    case openHandHeld(Date)
    case fistHeld(Date)
    case oneFingerHeld(Date)
    case threeFingersHeld(Date)
}

public struct CameraSessionClient: Sendable {
    public var activate: @Sendable (UUID) async throws -> Void
    public var isRunning: @Sendable () async -> Bool
    public var deactivate: @Sendable (UUID) async -> Void
    public var suspend: @Sendable () async -> Void
    public var switchCamera: @Sendable () async throws -> Void
    public var previewConnector: @Sendable () async -> CameraPreviewConnector
    public var handEvents: @Sendable () async -> AsyncStream<CameraHandEvent>
    public var capturePhoto: @Sendable () async throws -> Data
    public var prepareVideoRecording: @Sendable () async throws -> Void
    public var recordVideo: @Sendable (UUID, @escaping @Sendable () -> Void) async throws -> URL
    public var cancelVideoRecording: @Sendable () async -> Void
    public var cancelVideoRecordingForSession: @Sendable (UUID) async -> Void
    public var stopVideoRecording: @Sendable (UUID) async -> Void
    public var discardVideo: @Sendable (URL) async -> Void

    public init(
        activate: @escaping @Sendable (UUID) async throws -> Void,
        isRunning: @escaping @Sendable () async -> Bool,
        deactivate: @escaping @Sendable (UUID) async -> Void,
        suspend: @escaping @Sendable () async -> Void,
        switchCamera: @escaping @Sendable () async throws -> Void,
        previewConnector: @escaping @Sendable () async -> CameraPreviewConnector,
        handEvents: @escaping @Sendable () async -> AsyncStream<CameraHandEvent>,
        capturePhoto: @escaping @Sendable () async throws -> Data,
        prepareVideoRecording: @escaping @Sendable () async throws -> Void,
        recordVideo: @escaping @Sendable (
            UUID, @escaping @Sendable () -> Void
        ) async throws -> URL,
        cancelVideoRecording: @escaping @Sendable () async -> Void,
        cancelVideoRecordingForSession: @escaping @Sendable (UUID) async -> Void,
        stopVideoRecording: @escaping @Sendable (UUID) async -> Void,
        discardVideo: @escaping @Sendable (URL) async -> Void
    ) {
        self.activate = activate
        self.isRunning = isRunning
        self.deactivate = deactivate
        self.suspend = suspend
        self.switchCamera = switchCamera
        self.previewConnector = previewConnector
        self.handEvents = handEvents
        self.capturePhoto = capturePhoto
        self.prepareVideoRecording = prepareVideoRecording
        self.recordVideo = recordVideo
        self.cancelVideoRecording = cancelVideoRecording
        self.cancelVideoRecordingForSession = cancelVideoRecordingForSession
        self.stopVideoRecording = stopVideoRecording
        self.discardVideo = discardVideo
    }
}

extension CameraSessionClient: DependencyKey {
    public static let liveValue: CameraSessionClient = {
        let session = CameraSession()
        return CameraSessionClient(
            activate: { try await session.activate(owner: $0) },
            isRunning: { await session.isRunning() },
            deactivate: { await session.deactivate(owner: $0) },
            suspend: { await session.suspend() },
            switchCamera: { try await session.switchCamera() },
            previewConnector: { await session.previewConnector() },
            handEvents: { await session.handEvents() },
            capturePhoto: { try await session.capturePhoto() },
            prepareVideoRecording: { try await session.prepareVideoRecording() },
            recordVideo: { try await session.recordVideo(id: $0, onStarted: $1) },
            cancelVideoRecording: { await session.cancelVideoRecording() },
            cancelVideoRecordingForSession: { await session.cancelVideoRecording(id: $0) },
            stopVideoRecording: { await session.stopVideoRecording(id: $0) },
            discardVideo: { await session.discardVideo(at: $0) }
        )
    }()
}

extension DependencyValues {
    public var cameraSessionClient: CameraSessionClient {
        get { self[CameraSessionClient.self] }
        set { self[CameraSessionClient.self] = newValue }
    }
}
