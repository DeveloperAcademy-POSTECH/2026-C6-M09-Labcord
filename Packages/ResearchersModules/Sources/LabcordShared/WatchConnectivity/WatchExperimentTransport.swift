import Foundation
import WatchConnectivity

/// 즉시 명령은 sendMessage로만 전송하며 지연 큐에 보관하지 않습니다.
@MainActor
public final class WatchExperimentTransport {
    public static let commandKey = "experiment.command.v1"
    public static let responseKey = "experiment.response.v1"
    public static let snapshotKey = "experiment.snapshot.v1"

    public var refreshSnapshot: ((UUID) async -> Void)?
    private var refreshTask: Task<Void, Never>?
    public var receiveCommand: ((WatchExperimentCommand) -> WatchExperimentResponse)?
    private var transmissions: [UUID: UUID] = [:]
    private var pending: [UUID: CheckedContinuation<WatchExperimentResponse, Error>] = [:]
    private var deadlines: [UUID: Task<Void, Never>] = [:]
    private var subscribers: [UUID: AsyncStream<WatchExperimentSnapshot>.Continuation] = [:]
    private var latest: [UUID: WatchExperimentSnapshot] = [:]

    public init() {}

    public func send(_ command: WatchExperimentCommand, session: WCSession?) async throws
        -> WatchExperimentResponse {
        try Task.checkCancellation()
        guard let session, session.activationState == .activated, session.isReachable else {
            throw WatchExperimentError.notReachable
        }
        guard pending[command.requestID] == nil else { throw WatchExperimentError.phoneBusy }
        let data = try JSONEncoder().encode(command)
        let responseKey = Self.responseKey
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
                session.sendMessage([Self.commandKey: data]) { @Sendable [weak self] message in
                    let responseData = message[responseKey] as? Data
                    Task { @MainActor in
                        self?.handleReply(
                            responseData, command: command, transmissionID: transmissionID
                        )
                    }
                } errorHandler: { @Sendable [weak self] _ in
                    Task { @MainActor in
                        self?.finish(
                            command.requestID, transmissionID: transmissionID,
                            result: .failure(WatchExperimentError.resultUnknown)
                        )
                    }
                }
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
        if subscribers.isEmpty {
            refreshTask?.cancel()
            refreshTask = nil
        }
    }

    private func startRefreshing() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                for id in Array(latest.keys) { await refreshSnapshot?(id) }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    public func receiveSnapshot(_ data: Data) {
        guard let snapshot = try? JSONDecoder().decode(WatchExperimentSnapshot.self, from: data)
        else { return }
        let id = snapshot.experiment.id
        guard latest[id].map({ snapshot.revision > $0.revision }) ?? true else { return }
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
