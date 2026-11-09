import Foundation

@MainActor
final class WatchAudioStartGate {
    private(set) var isStarting = false
    private(set) var isStopping = false
    private var generation: UUID?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func begin() throws -> UUID {
        guard !isStarting, !isStopping else { throw CancellationError() }
        let next = UUID()
        generation = next
        isStarting = true
        return next
    }

    func beginStopping() -> Bool {
        guard !isStopping else { return false }
        isStopping = true
        return true
    }

    func finishStopping() {
        isStopping = false
    }

    func invalidate() -> Bool {
        guard isStarting else { return false }
        generation = nil
        return true
    }

    func cancelPending() async -> Bool {
        guard invalidate() else { return false }
        await withCheckedContinuation { waiters.append($0) }
        return true
    }

    func accepts(_ candidate: UUID) -> Bool {
        isStarting && generation == candidate
    }

    func finish() {
        generation = nil
        isStarting = false
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}
