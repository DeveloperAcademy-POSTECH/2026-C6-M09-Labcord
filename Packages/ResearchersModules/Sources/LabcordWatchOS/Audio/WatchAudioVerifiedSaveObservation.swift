import Foundation
import LabcordShared

@MainActor
public final class WatchAudioVerifiedSaveObservation {
    public let receipts: AsyncStream<WatchAudioReceipt>
    private let continuation: AsyncStream<WatchAudioReceipt>.Continuation
    private var reconciliationNeeded = false

    init(onTermination: @escaping @MainActor @Sendable () -> Void) {
        let (stream, continuation) = AsyncStream<WatchAudioReceipt>.makeStream(
            bufferingPolicy: .bufferingNewest(8)
        )
        receipts = stream
        self.continuation = continuation
        continuation.onTermination = { _ in
            Task { @MainActor in onTermination() }
        }
    }

    public func consumeReconciliationNeeded() -> Bool {
        defer { reconciliationNeeded = false }
        return reconciliationNeeded
    }

    public func cancel() {
        continuation.finish()
    }

    func publish(_ receipt: WatchAudioReceipt) {
        switch continuation.yield(receipt) {
        case .enqueued, .terminated:
            break
        case .dropped:
            reconciliationNeeded = true
        @unknown default:
            reconciliationNeeded = true
        }
    }
}

@MainActor
final class WeakWatchAudioVerifiedSaveObservation {
    weak var value: WatchAudioVerifiedSaveObservation?

    init(_ value: WatchAudioVerifiedSaveObservation) {
        self.value = value
    }
}
