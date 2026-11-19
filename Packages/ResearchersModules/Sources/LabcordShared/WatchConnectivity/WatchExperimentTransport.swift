import Foundation
import WatchConnectivity

@MainActor
public final class WatchExperimentTransport {
    public static let commandKey = "experiment.command.v1"
    public static let responseKey = "experiment.response.v1"
    public nonisolated static let backgroundCommandKey = "experiment.background.command.v1"
    public nonisolated static let backgroundResponseKey = "experiment.background.response.v1"
    public nonisolated static let listSnapshotKey = "experiment.list.snapshot.v1"
    public nonisolated static let listVersionKey = "experiment.list.version.v1"
    public static let snapshotKey = "experiment.snapshot.v1"
    public nonisolated static let screenKey = "screen.snapshot.v1"

    public var refreshSnapshot: ((UUID) async -> Void)?
    public var refreshScreen: (() async -> Void)?
    private var refreshTask: Task<Void, Never>?
    public var receiveCommand: ((WatchExperimentCommand) -> WatchExperimentResponse)?
    public private(set) var remoteEpoch: WatchStateEpoch?
    public var remoteEpochChanged: ((WatchStateEpoch) -> Void)?
    private var transmissions: [UUID: UUID] = [:]
    private var pending: [UUID: CheckedContinuation<WatchExperimentResponse, Error>] = [:]
    private var deadlines: [UUID: Task<Void, Never>] = [:]
    private struct SnapshotObserver {
        let experimentID: UUID
        let continuation: AsyncStream<WatchExperimentSnapshot>.Continuation
    }

    private var subscribers: [UUID: SnapshotObserver] = [:]
    private var latest: [UUID: WatchExperimentSnapshot] = [:]
    private var screenSubscribers: [UUID: AsyncStream<WatchScreenSnapshot>.Continuation] = [:]
    private var latestScreen: WatchScreenSnapshot?

    public init() {}

    public func acceptEpoch(_ epoch: WatchStateEpoch?) -> Bool {
        guard let epoch else { return remoteEpoch == nil }
        if let remoteEpoch {
            if epoch == remoteEpoch { return true }
            guard epoch.isNewer(than: remoteEpoch) else { return false }
        }
        remoteEpoch = epoch
        latest.removeAll()
        latestScreen = nil
        remoteEpochChanged?(epoch)
        return true
    }

    public func send(_ command: WatchExperimentCommand, session: WCSession?) async throws
        -> WatchExperimentResponse {
        try Task.checkCancellation()
        guard let session, WatchConnectivityState(session).canTransfer,
              session.isReachable else {
            throw WatchExperimentError.notReachable
        }
        let responseKey = Self.responseKey
        let id = command.requestID.uuidString
        let start = ContinuousClock.now
        return try await send(command) { data, reply, failure in
            WatchConnectivityDiagnostics.event("command.sent", id: id, bytes: data.count)
            session.sendMessage([Self.commandKey: data]) { @Sendable message in
                let data = message[responseKey] as? Data
                WatchConnectivityDiagnostics.reply(id: id, since: start, bytes: data?.count ?? 0)
                reply(data)
            } errorHandler: { @Sendable error in
                WatchConnectivityDiagnostics.failure("command.failed", id: id, error: error)
                failure()
            }
        }
    }

    func send(
        _ command: WatchExperimentCommand,
        transmit: (
            Data, @escaping @Sendable (Data?) -> Void, @escaping @Sendable () -> Void
        ) -> Void
    ) async throws -> WatchExperimentResponse {
        try Task.checkCancellation()
        guard pending[command.requestID] == nil else { throw WatchExperimentError.phoneBusy }
        let data = try JSONEncoder().encode(command)
        let transmissionID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[command.requestID] = continuation
                transmissions[command.requestID] = transmissionID
                deadlines[command.requestID] = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(3))
                    guard !Task.isCancelled else { return }
                    WatchConnectivityDiagnostics.event(
                        "command.timeout", id: command.requestID.uuidString
                    )
                    self?.finish(
                        command.requestID, transmissionID: transmissionID,
                        result: .failure(WatchExperimentError.deliveryTimeout)
                    )
                }
                transmit(data, { @Sendable [weak self] responseData in
                    Task { @MainActor in
                        self?.handleReply(
                            responseData, command: command, transmissionID: transmissionID
                        )
                    }
                }, { @Sendable [weak self] in
                    Task { @MainActor in
                        self?.finish(
                            command.requestID, transmissionID: transmissionID,
                            result: .failure(WatchExperimentError.resultUnknown)
                        )
                    }
                })
            }
        } onCancel: { [weak self] in
            Task { @MainActor in
                self?.finish(
                    command.requestID, transmissionID: transmissionID,
                    result: .failure(CancellationError())
                )
            }
        }
    }

    private func handleReply(
        _ responseData: Data?, command: WatchExperimentCommand, transmissionID: UUID
    ) {
        guard transmissions[command.requestID] == transmissionID else { return }
        guard let responseData,
              let response = try? JSONDecoder().decode(
                WatchExperimentResponse.self, from: responseData
              ), response.requestID == command.requestID,
              response.version == WatchExperimentCommand.schemaVersion,
              response.snapshot.map({ snapshot in
                  command.experimentID.map { $0 == snapshot.experiment.id } ?? true
              }) ?? true else {
            finish(command.requestID, transmissionID: transmissionID, result: .failure(
                WatchExperimentError.invalidPayload
            ))
            return
        }
        if let screen = response.screen { receiveScreen(screen) }
        if let snapshot = response.snapshot { receiveSnapshot(snapshot) }
        let snapshot = response.snapshot.flatMap { latest[$0.experiment.id] }
        let screen = response.screen == nil ? nil : latestScreen
        if (command.operation == .snapshot && response.snapshot != nil && snapshot == nil)
            || (command.operation == .screen && response.screen != nil && screen == nil) {
            finish(command.requestID, transmissionID: transmissionID, result: .failure(
                WatchExperimentError.staleRevision
            ))
            return
        }
        let current = WatchExperimentResponse(
            version: response.version, requestID: response.requestID, phase: response.phase,
            experiments: response.experiments, snapshot: snapshot, error: response.error,
            startToken: response.startToken, record: response.record,
            queriedRequestID: response.queriedRequestID, screen: screen,
            listVersion: response.listVersion
        )
        finish(command.requestID, transmissionID: transmissionID, result: .success(current))
    }

    private func finish(
        _ id: UUID, transmissionID: UUID, result: Result<WatchExperimentResponse, Error>
    ) {
        guard transmissions[id] == transmissionID else { return }
        transmissions.removeValue(forKey: id)
        deadlines.removeValue(forKey: id)?.cancel()
        pending.removeValue(forKey: id)?.resume(with: result)
    }

    public func stream(experimentID: UUID) -> AsyncStream<WatchExperimentSnapshot> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(32)) { continuation in
            subscribers[id] = SnapshotObserver(
                experimentID: experimentID, continuation: continuation
            )
            startRefreshing()
            if let snapshot = latest[experimentID] { continuation.yield(snapshot) }
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.removeSubscriber(id) }
            }
        }
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers.removeValue(forKey: id)
        if subscribers.isEmpty && screenSubscribers.isEmpty {
            refreshTask?.cancel()
            refreshTask = nil
        }
    }

    private func startRefreshing() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard self != nil else { return }
                await self?.refreshObservedState()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func refreshObservedState() async {
        if !screenSubscribers.isEmpty { await refreshScreen?() }
        let experimentIDs = Set(subscribers.values.map(\.experimentID))
        for id in experimentIDs {
            guard !Task.isCancelled else { return }
            guard subscribers.values.contains(where: { $0.experimentID == id }) else { continue }
            await refreshSnapshot?(id)
        }
    }

    public func receiveSnapshot(_ data: Data) {
        guard let snapshot = try? JSONDecoder().decode(WatchExperimentSnapshot.self, from: data)
        else { return }
        receiveSnapshot(snapshot)
    }

    private func receiveSnapshot(_ snapshot: WatchExperimentSnapshot) {
        guard acceptEpoch(snapshot.epoch) else { return }
        let id = snapshot.experiment.id
        guard latest[id].map({ snapshot.isNewer(than: $0) }) ?? true else { return }
        latest[id] = snapshot
        for subscriber in subscribers.values where subscriber.experimentID == id {
            subscriber.continuation.yield(snapshot)
        }
    }

    public func reply(to data: Data) -> Data? {
        guard let command = try? JSONDecoder().decode(WatchExperimentCommand.self, from: data)
        else { return nil }
        let id = command.requestID.uuidString
        WatchConnectivityDiagnostics.event("command.received", id: id, bytes: data.count)
        let response = receiveCommand?(command) ?? WatchExperimentResponse(
            requestID: command.requestID, phase: .failed, error: .phoneBusy
        )
        let encoded = try? JSONEncoder().encode(response)
        WatchConnectivityDiagnostics.event("command.replied", id: id, bytes: encoded?.count ?? 0)
        return encoded
    }
}

extension WatchExperimentTransport {
    public func screens() -> AsyncStream<WatchScreenSnapshot> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            screenSubscribers[id] = continuation
            if let latestScreen { continuation.yield(latestScreen) }
            startRefreshing()
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.removeScreenSubscriber(id) }
            }
        }
    }

    public func receiveScreen(_ data: Data) {
        guard data.count <= 16_384,
              let screen = try? JSONDecoder().decode(WatchScreenSnapshot.self, from: data)
        else { return }
        receiveScreen(screen)
    }

    public func receiveScreen(_ screen: WatchScreenSnapshot) {
        guard screen.isValid, acceptEpoch(screen.epoch) else { return }
        if let previous = latestScreen {
            guard screen.revision >= previous.revision else { return }
            if screen.revision == previous.revision {
                guard screen.recordedAt > previous.recordedAt,
                      screen.hasSameContent(as: previous) else { return }
            }
        }
        latestScreen = screen
        screenSubscribers.values.forEach { $0.yield(screen) }
    }

    private func removeScreenSubscriber(_ id: UUID) {
        screenSubscribers.removeValue(forKey: id)
        if subscribers.isEmpty && screenSubscribers.isEmpty {
            refreshTask?.cancel()
            refreshTask = nil
        }
    }
}
