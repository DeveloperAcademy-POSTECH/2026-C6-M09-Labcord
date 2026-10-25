import ComposableArchitecture

public struct CameraSessionClient: Sendable {
    public var start: @Sendable () async throws -> Void
    public var stop: @Sendable () async -> Void
    public var previewConnector: @Sendable () async -> CameraPreviewConnector

    public init(
        start: @escaping @Sendable () async throws -> Void,
        stop: @escaping @Sendable () async -> Void,
        previewConnector: @escaping @Sendable () async -> CameraPreviewConnector
    ) {
        self.start = start
        self.stop = stop
        self.previewConnector = previewConnector
    }
}

extension CameraSessionClient: DependencyKey {
    public static let liveValue: CameraSessionClient = {
        let session = CameraSession()
        return CameraSessionClient(
            start: { try await session.start() },
            stop: { await session.stop() },
            previewConnector: { await session.previewConnector() }
        )
    }()
}

extension DependencyValues {
    public var cameraSessionClient: CameraSessionClient {
        get { self[CameraSessionClient.self] }
        set { self[CameraSessionClient.self] = newValue }
    }
}
