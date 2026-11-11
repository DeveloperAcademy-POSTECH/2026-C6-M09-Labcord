import CoreGraphics
import Foundation

nonisolated final class CameraHandOverlayHub: @unchecked Sendable {
    struct Segment: Sendable {
        let start: CGPoint
        let end: CGPoint
    }

    struct Frame: Sendable {
        let segments: [Segment]
        let joints: [CGPoint]
        let imageSize: CGSize
        let videoRotationAngle: CGFloat
        let isVideoMirrored: Bool
    }

    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<Frame>.Continuation] = [:]

    func stream() -> AsyncStream<Frame> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Frame>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        continuation.onTermination = { [weak self] _ in self?.remove(id) }
        lock.withLock { continuations[id] = continuation }
        return stream
    }

    func emit(_ frame: Frame) {
        let recipients = lock.withLock { Array(continuations.values) }
        for continuation in recipients {
            continuation.yield(frame)
        }
    }

    private func remove(_ id: UUID) {
        lock.withLock { _ = continuations.removeValue(forKey: id) }
    }
}
