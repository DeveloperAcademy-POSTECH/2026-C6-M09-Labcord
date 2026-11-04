import Foundation

/// The Watch UI owns its countdown; this gate only accepts an explicit save or cancel decision.
@MainActor
final class WatchAudioReviewGate {
    private var waiters: [UUID: CheckedContinuation<Bool, Never>] = [:]

    func contains(_ id: UUID) -> Bool { waiters[id] != nil }

    func wait(_ id: UUID) async -> Bool {
        await withCheckedContinuation { waiters[id] = $0 }
    }

    func resolve(_ id: UUID, save: Bool) {
        waiters.removeValue(forKey: id)?.resume(returning: save)
    }

    func cancelAll() {
        for id in Array(waiters.keys) { resolve(id, save: false) }
    }
}
