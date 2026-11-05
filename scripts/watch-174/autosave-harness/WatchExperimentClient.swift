// 검사 경계: 실제 WatchConnectivity나 성공 응답을 대체하지 않는다.
import ComposableArchitecture
import LabcordShared

public enum WatchConnectionStatus: Equatable, Sendable {
    case activating, activationFailed, unsupported, unreachable, reachable
}

public struct WatchExperimentClient: Sendable {
    public var send: @Sendable (WatchExperimentCommand) async throws -> WatchExperimentResponse
    public var snapshots: @Sendable () async -> AsyncStream<WatchExperimentSnapshot>
    public var isReachable: @Sendable () async -> Bool
    public var connectionStatus: @Sendable () async -> WatchConnectionStatus = { .unreachable }
    public var retryActivation: @Sendable () async -> Void = {}
}

extension WatchExperimentClient: DependencyKey {
    public static let liveValue = WatchExperimentClient(
        send: { _ in throw WatchExperimentError.resultUnknown },
        snapshots: { AsyncStream { $0.finish() } },
        isReachable: { false }
    )
}

extension DependencyValues {
    public var watchExperimentClient: WatchExperimentClient {
        get { self[WatchExperimentClient.self] }
        set { self[WatchExperimentClient.self] = newValue }
    }
}
