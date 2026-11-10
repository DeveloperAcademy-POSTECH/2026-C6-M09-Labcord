import Foundation
import WatchConnectivity

@MainActor
public final class WatchExperimentTransport {
    public static let commandKey = "experiment.command.v1"
    public static let responseKey = "experiment.response.v1"
    public static let snapshotKey = "experiment.snapshot.v1"
    public nonisolated static let screenKey = "screen.snapshot.v1"

    public var refreshSnapshot: ((UUID) async -> Void)?
    public var refreshScreen: (() async -> Void)?
    private var refreshTask: Task<Void, Never>?
    public var receiveCommand: ((WatchExperimentCommand) -> WatchExperimentResponse)?
    private var transmissions: [UUID: UUID] = [:]
    private var pending: [UUID: CheckedContinuation<WatchExperimentResponse, Error>] = [:]
    private var deadlines: [UUID: Task<Void, Never>] = [:]
    private var subscribers: [UUID: AsyncStream<WatchExperimentSnapshot>.Continuation] = [:]
    private var latest: [UUID: WatchExperimentSnapshot] = [:]
    private var screenSubscribers: [UUID: AsyncStream<WatchScreenSnapshot>.Continuation] = [:]
    private var latestScreen: WatchScreenSnapshot?

    public init() {}

    public func send(_ command: WatchExperimentCommand, session: WCSession?) async throws
        -> WatchExperimentResponse {
        try Task.checkCancellation()
        guard let session, session.activationState == .activated, session.isReachable else {
            throw WatchExperimentError.notReachable
        }
        let responseKey = Self.responseKey
        return try await send(command) { data, reply, failure in
            session.sendMessage([Self.commandKey: data]) { @Sendable message in
                reply(message[responseKey] as? Data)
            } errorHandler: { @Sendable _ in
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
        if let screen = response.screen, let data = try? JSONEncoder().encode(screen) {
            receiveScreen(data)
        }
        if let snapshot = response.snapshot,
           let data = try? JSONEncoder().encode(snapshot) {
            receiveSnapshot(data)
        }
        finish(command.requestID, transmissionID: transmissionID, result: .success(response))
    }

    private func finish(
        _ id: UUID, transmissionID: UUID, result: Result<WatchExperimentResponse, Error>
    ) {
        guard transmissions[id] == transmissionID else { return }
        transmissions.removeValue(forKey: id)
        deadlines.removeValue(forKey: id)?.cancel()
        pending.removeValue(forKey: id)?.resume(with: result)
    }

    public func stream() -> AsyncStream<WatchExperimentSnapshot> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(32)) { continuation in
            subscribers[id] = continuation
            startRefreshing()
            for snapshot in latest.values { continuation.yield(snapshot) }
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
                guard let self else { return }
                await refreshScreen?()
                for id in Array(latest.keys) { await refreshSnapshot?(id) }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    public func receiveSnapshot(_ data: Data) {
        guard let snapshot = try? JSONDecoder().decode(WatchExperimentSnapshot.self, from: data)
        else { return }
        let id = snapshot.experiment.id
        if let previous = latest[id] {
            guard snapshot.revision >= previous.revision else { return }
            if snapshot.revision == previous.revision {
                guard snapshot.recordedAt > previous.recordedAt,
                      hasSameState(snapshot, as: previous) else { return }
            }
        }
        latest[id] = snapshot
        for subscriber in subscribers.values { subscriber.yield(snapshot) }
    }

    public func reply(to data: Data) -> Data? {
        guard let command = try? JSONDecoder().decode(WatchExperimentCommand.self, from: data)
        else { return nil }
        let response = receiveCommand?(command) ?? WatchExperimentResponse(
            requestID: command.requestID, phase: .failed, error: .phoneBusy
        )
        return try? JSONEncoder().encode(response)
    }
}

private extension WatchExperimentTransport {
    func hasSameState(
        _ snapshot: WatchExperimentSnapshot, as previous: WatchExperimentSnapshot
    ) -> Bool {
        guard snapshot.experiment == previous.experiment, snapshot.mode == previous.mode,
              snapshot.phoneSessionActive == previous.phoneSessionActive,
              snapshot.protocolTimerSeconds == previous.protocolTimerSeconds,
              snapshot.timers.count == previous.timers.count else { return false }
        return zip(snapshot.timers, previous.timers).allSatisfy { current, old in
            guard current.id == old.id, current.durationSeconds == old.durationSeconds,
                  current.status == old.status else { return false }
            if current.status == .running {
                let end = current.measuredAt.addingTimeInterval(Double(current.remainingSeconds))
                let oldEnd = old.measuredAt.addingTimeInterval(Double(old.remainingSeconds))
                return abs(end.timeIntervalSince(oldEnd)) < 0.000_001
            }
            return current.remainingSeconds == old.remainingSeconds
        }
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
              let screen = try? JSONDecoder().decode(WatchScreenSnapshot.self, from: data),
              screen.isValid else { return }
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
