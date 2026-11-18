import Foundation

extension ProtocolAnalysisJobManager {
    public func updates() -> AsyncStream<ProtocolAnalysisJobSnapshot> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<ProtocolAnalysisJobSnapshot>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        listeners[id] = continuation
        if let value = try? snapshot() { continuation.yield(value) }
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeListener(id) }
        }
        return stream
    }

    func publish() {
        guard let value = try? snapshot() else { return }
        for listener in listeners.values { listener.yield(value) }
    }

    private func removeListener(_ id: UUID) { listeners[id] = nil }
}
