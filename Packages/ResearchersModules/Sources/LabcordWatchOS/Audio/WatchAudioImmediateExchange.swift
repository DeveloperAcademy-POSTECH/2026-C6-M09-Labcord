import Foundation
import LabcordShared
import WatchConnectivity

@MainActor
public final class WatchAudioImmediateExchange {
    private var pending: [UUID: CheckedContinuation<WatchAudioReceipt, Error>] = [:]

    public init() {}

    public func send(_ message: WatchAudioMessage) async throws -> WatchAudioReceipt {
        let state = WatchConnectivityState(.default)
        guard state.canTransfer, state.reachable else {
            throw WatchExperimentError.notReachable
        }
        let data = try JSONEncoder().encode(message)
        let id = UUID()
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            WCSession.default.sendMessageData(data) { @Sendable [weak self] reply in
                Task { @MainActor in
                    self?.resolve(id, result: Result {
                        try JSONDecoder().decode(WatchAudioReceipt.self, from: reply)
                    })
                }
            } errorHandler: { @Sendable [weak self] error in
                Task { @MainActor in self?.resolve(id, result: .failure(error)) }
            }
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                self?.resolve(id, result: .failure(WatchExperimentError.deliveryTimeout))
            }
        }
    }

    private func resolve(_ id: UUID, result: Result<WatchAudioReceipt, Error>) {
        pending.removeValue(forKey: id)?.resume(with: result)
    }
}
