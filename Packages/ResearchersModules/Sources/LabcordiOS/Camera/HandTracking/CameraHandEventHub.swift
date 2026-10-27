import Foundation

nonisolated final class CameraHandEventHub: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<CameraHandEvent>.Continuation] = [:]

    func stream() -> AsyncStream<CameraHandEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<CameraHandEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        continuation.onTermination = { [weak self] _ in self?.remove(id) }

        lock.withLock { continuations[id] = continuation }
        return stream
    }

    func emit(_ event: CameraHandEvent) {
        let recipients = lock.withLock { Array(continuations.values) }

        for continuation in recipients {
            continuation.yield(event)
        }
    }

    private func remove(_ id: UUID) {
        lock.withLock { _ = continuations.removeValue(forKey: id) }
    }
}
