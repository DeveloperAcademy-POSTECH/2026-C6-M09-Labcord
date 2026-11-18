import ComposableArchitecture
import Foundation
import LabcordShared

public enum WatchConnectionStatus: Equatable, Sendable {
    case activating
    case activationFailed
    case unsupported
    case unreachable
    case reachable
}

public struct WatchExperimentClient: Sendable {
    public var send: @Sendable (WatchExperimentCommand) async throws -> WatchExperimentResponse
    public var snapshots: @Sendable () async -> AsyncStream<WatchExperimentSnapshot>
    private var scopedSnapshots: (@Sendable (UUID) async -> AsyncStream<WatchExperimentSnapshot>)?
    public var screens: @Sendable () async -> AsyncStream<WatchScreenSnapshot>
    public var isReachable: @Sendable () async -> Bool
    public var connectionStatus: @Sendable () async -> WatchConnectionStatus
    public var retryActivation: @Sendable () async -> Void
    public var list: @Sendable () async throws -> [WatchExperimentSummary]
    public var lists: @Sendable () async -> AsyncStream<[WatchExperimentSummary]>
    public var cachedList: @Sendable () async -> [WatchExperimentSummary]?
    public var requestPhoneSession: @Sendable (UUID) async -> Void
    public var cancelPhoneSession: @Sendable (UUID) async -> Void
    public var enterPhoneSession: @Sendable (UUID) async -> Void
    public var leavePhoneSession: @Sendable (UUID) async -> Void

    public init(
        send: @escaping @Sendable (WatchExperimentCommand) async throws -> WatchExperimentResponse,
        snapshots: @escaping @Sendable () async -> AsyncStream<WatchExperimentSnapshot>,
        isReachable: @escaping @Sendable () async -> Bool,
        connectionStatus: @escaping @Sendable () async -> WatchConnectionStatus,
        retryActivation: @escaping @Sendable () async -> Void,
        list: @escaping @Sendable () async throws -> [WatchExperimentSummary] = { [] },
        lists: @escaping @Sendable () async -> AsyncStream<[WatchExperimentSummary]> = {
            AsyncStream { $0.finish() }
        },
        cachedList: @escaping @Sendable () async -> [WatchExperimentSummary]? = { nil },
        requestPhoneSession: @escaping @Sendable (UUID) async -> Void = { _ in },
        cancelPhoneSession: @escaping @Sendable (UUID) async -> Void = { _ in },
        enterPhoneSession: @escaping @Sendable (UUID) async -> Void = { _ in },
        leavePhoneSession: @escaping @Sendable (UUID) async -> Void = { _ in },
        screens: @escaping @Sendable () async -> AsyncStream<WatchScreenSnapshot> = {
            AsyncStream { $0.finish() }
        },
        scopedSnapshots: (@Sendable (UUID) async -> AsyncStream<WatchExperimentSnapshot>)? = nil
    ) {
        self.send = send
        self.snapshots = snapshots
        self.scopedSnapshots = scopedSnapshots
        self.screens = screens
        self.isReachable = isReachable
        self.connectionStatus = connectionStatus
        self.retryActivation = retryActivation
        self.list = list
        self.lists = lists
        self.cachedList = cachedList
        self.requestPhoneSession = requestPhoneSession
        self.cancelPhoneSession = cancelPhoneSession
        self.enterPhoneSession = enterPhoneSession
        self.leavePhoneSession = leavePhoneSession
    }

    public func snapshots(for experimentID: UUID) async -> AsyncStream<WatchExperimentSnapshot> {
        if let scopedSnapshots { return await scopedSnapshots(experimentID) }
        let stream = await snapshots()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task {
                for await snapshot in stream where snapshot.experiment.id == experimentID {
                    continuation.yield(snapshot)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

extension WatchExperimentClient: DependencyKey {
    public static var liveValue: Self {
        @Dependency(\.watchConnectivitySession) var connectivity
        return Self(
            send: { command in
                await connectivity.activate()
                let response = try await connectivity.experiments.send(
                    command, session: connectivity.session
                )
                if let record = response.record {
                    guard record.experimentID == command.experimentID else {
                        throw WatchExperimentError.invalidPayload
                    }
                    let data = try JSONEncoder().encode(record)
                    await connectivity.records.receive(data)
                }
                return response
            },
            snapshots: {
                await snapshotStream(connectivity)
            },
            isReachable: {
                await connectivity.activate()
                return await connectivity.session?.isReachable ?? false
            },
            connectionStatus: {
                await connectionStatus(connectivity)
            },
            retryActivation: {
                await connectivity.retryActivation()
            },
            list: {
                try await connectivity.loadExperiments()
            },
            lists: {
                await connectivity.experimentLists()
            },
            cachedList: {
                await connectivity.cachedExperiments()
            },
            requestPhoneSession: { id in
                await connectivity.requestPhoneSession(id)
            },
            cancelPhoneSession: { id in
                await connectivity.cancelPhoneSession(id)
            },
            enterPhoneSession: { id in
                await connectivity.enterPhoneSession(id)
            },
            leavePhoneSession: { id in
                await connectivity.leavePhoneSession(id)
            },
            screens: {
                await connectivity.activate()
                return await screenStream(connectivity)
            },
            scopedSnapshots: { experimentID in
                await snapshotStream(connectivity, experimentID: experimentID)
            }
        )
    }

    @MainActor
    private static func connectionStatus(
        _ connectivity: WatchConnectivitySession
    ) -> WatchConnectionStatus {
        guard let session = connectivity.session else { return .unsupported }
        if session.activationState == .activated {
            return session.isReachable ? .reachable : .unreachable
        }
        if connectivity.activationFailed { return .activationFailed }
        return .activating
    }

    @MainActor
    private static func snapshotStream(
        _ connectivity: WatchConnectivitySession, experimentID: UUID? = nil
    ) -> AsyncStream<WatchExperimentSnapshot> {
        connectivity.activate()
        if let data = connectivity.session?.receivedApplicationContext[
            WatchExperimentTransport.snapshotKey
        ] as? Data {
            connectivity.experiments.receiveSnapshot(data)
        }
        connectivity.experiments.refreshSnapshot = { [weak connectivity] id in
            guard let connectivity else { return }
            _ = try? await connectivity.experiments.send(
                WatchExperimentCommand(operation: .snapshot, experimentID: id),
                session: connectivity.session
            )
        }
        return connectivity.experiments.stream(for: experimentID)
    }

    @MainActor
    private static func screenStream(
        _ connectivity: WatchConnectivitySession
    ) -> AsyncStream<WatchScreenSnapshot> {
        if let data = connectivity.session?.receivedApplicationContext[
            WatchExperimentTransport.screenKey
        ] as? Data {
            connectivity.experiments.receiveScreen(data)
        }
        connectivity.experiments.refreshScreen = { [weak connectivity] in
            guard let connectivity else { return }
            _ = try? await connectivity.experiments.send(
                WatchExperimentCommand(operation: .screen), session: connectivity.session
            )
        }
        return connectivity.experiments.screens()
    }

    public static let testValue = Self(
        send: { _ in throw WatchExperimentError.resultUnknown },
        snapshots: unimplemented(
            "WatchExperimentClient.snapshots", placeholder: AsyncStream { $0.finish() }
        ),
        isReachable: unimplemented("WatchExperimentClient.isReachable", placeholder: false),
        connectionStatus: unimplemented(
            "WatchExperimentClient.connectionStatus", placeholder: .unsupported
        ),
        retryActivation: unimplemented("WatchExperimentClient.retryActivation"),
        list: unimplemented("WatchExperimentClient.list", placeholder: [])
    )
}

extension DependencyValues {
    public var watchExperimentClient: WatchExperimentClient {
        get { self[WatchExperimentClient.self] }
        set { self[WatchExperimentClient.self] = newValue }
    }
}
