import ComposableArchitecture
import Foundation

public enum CameraHandEvent: Equatable, Sendable {
    case fistHeld(Date)
}

public struct CameraSessionClient: Sendable {
    public var activate: @Sendable (UUID) async throws -> Void
    public var deactivate: @Sendable (UUID) async -> Void
    public var switchCamera: @Sendable () async throws -> Void
    public var previewConnector: @Sendable () async -> CameraPreviewConnector
    public var handEvents: @Sendable () async -> AsyncStream<CameraHandEvent>
    public var capturePhoto: @Sendable () async throws -> Data

    public init(
        activate: @escaping @Sendable (UUID) async throws -> Void,
        deactivate: @escaping @Sendable (UUID) async -> Void,
        switchCamera: @escaping @Sendable () async throws -> Void,
        previewConnector: @escaping @Sendable () async -> CameraPreviewConnector,
        handEvents: @escaping @Sendable () async -> AsyncStream<CameraHandEvent>,
        capturePhoto: @escaping @Sendable () async throws -> Data
    ) {
        self.activate = activate
        self.deactivate = deactivate
        self.switchCamera = switchCamera
        self.previewConnector = previewConnector
        self.handEvents = handEvents
        self.capturePhoto = capturePhoto
    }
}

extension CameraSessionClient: DependencyKey {
    public static let liveValue: CameraSessionClient = {
        let session = CameraSession()
        return CameraSessionClient(
            activate: { try await session.activate(owner: $0) },
            deactivate: { await session.deactivate(owner: $0) },
            switchCamera: { try await session.switchCamera() },
            previewConnector: { await session.previewConnector() },
            handEvents: { await session.handEvents() },
            capturePhoto: { try await session.capturePhoto() }
        )
    }()
}

extension DependencyValues {
    public var cameraSessionClient: CameraSessionClient {
        get { self[CameraSessionClient.self] }
        set { self[CameraSessionClient.self] = newValue }
    }
}
