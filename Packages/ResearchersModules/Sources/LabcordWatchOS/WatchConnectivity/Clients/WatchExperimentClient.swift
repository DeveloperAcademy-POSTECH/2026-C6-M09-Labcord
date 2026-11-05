import ComposableArchitecture
import Foundation
import LabcordShared

public struct WatchExperimentClient: Sendable {
    public var send: @Sendable (WatchExperimentCommand) async throws -> WatchExperimentResponse
    public var snapshots: @Sendable () async -> AsyncStream<WatchExperimentSnapshot>
    public var isReachable: @Sendable () async -> Bool

    public init(
        send: @escaping @Sendable (WatchExperimentCommand) async throws -> WatchExperimentResponse,
        snapshots: @escaping @Sendable () async -> AsyncStream<WatchExperimentSnapshot>,
        isReachable: @escaping @Sendable () async -> Bool
    ) {
        self.send = send
        self.snapshots = snapshots
        self.isReachable = isReachable
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
                await connectivity.activate()
                if let data = await connectivity.session?.receivedApplicationContext[
                    WatchExperimentTransport.snapshotKey
                ] as? Data {
                    await connectivity.experiments.receiveSnapshot(data)
                }
                return await snapshotStream(connectivity)

            },
            isReachable: {
                await connectivity.activate()
                return await connectivity.session?.isReachable ?? false
            }
        )
    }

    @MainActor
    private static func snapshotStream(
        _ connectivity: WatchConnectivitySession
    ) -> AsyncStream<WatchExperimentSnapshot> {
        connectivity.experiments.refreshSnapshot = { [weak connectivity] id in
            guard let connectivity else { return }
            _ = try? await connectivity.experiments.send(
                WatchExperimentCommand(operation: .snapshot, experimentID: id),
                session: connectivity.session
            )
        }
        return connectivity.experiments.stream()
    }

    public static let testValue = Self(
        send: { _ in throw WatchExperimentError.resultUnknown },
        snapshots: unimplemented(
            "WatchExperimentClient.snapshots", placeholder: AsyncStream { $0.finish() }
        ),
        isReachable: unimplemented("WatchExperimentClient.isReachable", placeholder: false)
    )
}

extension DependencyValues {
    public var watchExperimentClient: WatchExperimentClient {
        get { self[WatchExperimentClient.self] }
        set { self[WatchExperimentClient.self] = newValue }
    }
}
