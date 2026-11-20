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
    public var snapshots: @Sendable (UUID) async -> AsyncStream<WatchExperimentSnapshot>
    public var screens: @Sendable () async -> AsyncStream<WatchScreenSnapshot>
    public var isReachable: @Sendable () async -> Bool
    public var connectionStatus: @Sendable () async -> WatchConnectionStatus
    public var retryActivation: @Sendable () async -> Void
    public var list: @Sendable () async throws -> WatchExperimentList
    public var lists: @Sendable () async -> AsyncStream<WatchExperimentListUpdate>
    public var requestPhoneSession: @Sendable (WatchSessionOpenRequest) async throws -> Void
    public var cancelPhoneSession: @Sendable (WatchSessionOpenRequest) async -> Void
    public var enterPhoneSession: @Sendable (UUID) async -> Void
    public var leavePhoneSession: @Sendable (UUID) async -> Void

    public init(
        send: @escaping @Sendable (WatchExperimentCommand) async throws -> WatchExperimentResponse,
        snapshots: @escaping @Sendable (UUID) async -> AsyncStream<WatchExperimentSnapshot>,
        isReachable: @escaping @Sendable () async -> Bool,
        connectionStatus: @escaping @Sendable () async -> WatchConnectionStatus,
        retryActivation: @escaping @Sendable () async -> Void,
        list: @escaping @Sendable () async throws -> WatchExperimentList = {
            throw WatchExperimentError.notReachable
        },
        lists: @escaping @Sendable () async -> AsyncStream<WatchExperimentListUpdate> = {
            AsyncStream { $0.finish() }
        },
        requestPhoneSession: @escaping @Sendable (WatchSessionOpenRequest) async throws -> Void
            = { _ in throw WatchExperimentError.notReachable },
        cancelPhoneSession: @escaping @Sendable (WatchSessionOpenRequest) async -> Void = { _ in },
        enterPhoneSession: @escaping @Sendable (UUID) async -> Void = { _ in },
        leavePhoneSession: @escaping @Sendable (UUID) async -> Void = { _ in },
        screens: @escaping @Sendable () async -> AsyncStream<WatchScreenSnapshot> = {
            AsyncStream { $0.finish() }
        }
    ) {
        self.send = send
        self.snapshots = snapshots
        self.screens = screens
        self.isReachable = isReachable
        self.connectionStatus = connectionStatus
        self.retryActivation = retryActivation
        self.list = list
        self.lists = lists
        self.requestPhoneSession = requestPhoneSession
        self.cancelPhoneSession = cancelPhoneSession
        self.enterPhoneSession = enterPhoneSession
        self.leavePhoneSession = leavePhoneSession
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
                    await connectivity.records.receive(record)
                }
                return response
            },
            snapshots: { experimentID in
                await connectivity.activate()
                if let data = await connectivity.session?.receivedApplicationContext[
                    WatchExperimentTransport.snapshotKey
                ] as? Data {
                    await connectivity.experiments.receiveSnapshot(data)
                }
                return await snapshotStream(connectivity, experimentID: experimentID)

            },
            isReachable: {
                await connectivity.activate()
                return await canInteract(connectivity)
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
            requestPhoneSession: { request in
                try await connectivity.requestPhoneSession(request)
            },
            cancelPhoneSession: { request in
                await connectivity.cancelPhoneSession(request)
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
            }
        )
    }

    @MainActor
    private static func connectionStatus(
        _ connectivity: WatchConnectivitySession
    ) -> WatchConnectionStatus {
        guard let session = connectivity.session else { return .unsupported }
        if session.activationState == .activated {
            return canInteract(connectivity) ? .reachable : .unreachable
        }
        if connectivity.activationFailed { return .activationFailed }
        return .activating
    }

    @MainActor
    private static func canInteract(_ connectivity: WatchConnectivitySession) -> Bool {
        guard let session = connectivity.session else { return false }
        let state = WatchConnectivityState(session)
        return state.canTransfer && state.reachable
    }

    @MainActor
    private static func snapshotStream(
        _ connectivity: WatchConnectivitySession, experimentID: UUID
    ) -> AsyncStream<WatchExperimentSnapshot> {
        connectivity.experiments.refreshSnapshot = { [weak connectivity] id in
            guard let connectivity, canInteract(connectivity) else { return }
            _ = try? await connectivity.experiments.send(
                WatchExperimentCommand(operation: .snapshot, experimentID: id),
                session: connectivity.session
            )
        }
        return connectivity.experiments.stream(experimentID: experimentID)
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
            guard let connectivity, canInteract(connectivity) else { return }
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
        list: unimplemented(
            "WatchExperimentClient.list", placeholder: WatchExperimentList(experiments: [])
        )
    )
}

extension DependencyValues {
    public var watchExperimentClient: WatchExperimentClient {
        get { self[WatchExperimentClient.self] }
        set { self[WatchExperimentClient.self] = newValue }
    }
}
