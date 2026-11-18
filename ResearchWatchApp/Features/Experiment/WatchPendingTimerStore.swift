import Foundation
import LabcordShared

struct WatchPendingTimer: Codable, Equatable, Identifiable, Sendable {
    let experimentID: UUID
    var timer: ExperimentTimer
    var lastObservedAt: Date

    var id: UUID { timer.id }

    func snapshot(at date: Date) -> WatchTimerSnapshot {
        let remaining = timer.remainingSeconds(at: date)
        let status: WatchTimerSnapshot.Status = remaining == 0 || timer.status == .finished
            ? .finished : timer.status == .paused ? .paused : .running
        let pauseDuration = timer.pauseIntervals.reduce(0.0) { total, pause in
            total + max(0, (pause.resumedAt ?? pause.pausedAt).timeIntervalSince(pause.pausedAt))
        }
        let end = timer.startedAt.addingTimeInterval(Double(timer.durationSeconds) + pauseDuration)
        let measuredAt = status == .running
            ? end.addingTimeInterval(-Double(remaining)) : date
        return WatchTimerSnapshot(
            id: id, durationSeconds: timer.durationSeconds,
            remainingSeconds: remaining, status: status,
            measuredAt: measuredAt, startedAt: timer.startedAt
        )
    }
}

@MainActor
final class WatchPendingTimerStore {
    static let shared = WatchPendingTimerStore()

    private let key = "watch.pendingTimers.v1"
    private(set) var timers: [WatchPendingTimer]
    private var heartbeat: Task<Void, Never>?

    private init() {
        let data = UserDefaults.standard.data(forKey: key)
        let stored = data.flatMap { try? JSONDecoder().decode([WatchPendingTimer].self, from: $0) }
        timers = (stored ?? []).map { pending in
            var pending = pending
            if pending.timer.status == .running {
                pending.timer.pause(at: pending.lastObservedAt)
            }
            return pending
        }
        save()
    }

    func timers(for experimentID: UUID) -> [WatchPendingTimer] {
        timers.filter { $0.experimentID == experimentID }
    }

    func add(_ pending: WatchPendingTimer) {
        guard !timers.contains(where: { $0.id == pending.id }) else { return }
        timers.append(pending)
        save()
        startHeartbeat()
    }

    func update(_ pending: WatchPendingTimer) {
        guard let index = timers.firstIndex(where: { $0.id == pending.id }) else { return }
        timers[index] = pending
        save()
        startHeartbeat()
    }

    func remove(_ id: UUID) {
        timers.removeAll { $0.id == id }
        save()
        if timers.isEmpty {
            heartbeat?.cancel()
            heartbeat = nil
        }
    }

    private func startHeartbeat() {
        guard heartbeat == nil, timers.contains(where: { $0.timer.status == .running }) else {
            return
        }
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                guard timers.contains(where: { $0.timer.status == .running }) else {
                    heartbeat = nil
                    return
                }
                let date = Date()
                for index in timers.indices where timers[index].timer.status == .running {
                    timers[index].timer.finishIfNeeded(at: date)
                    timers[index].lastObservedAt = date
                }
                save()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(timers), forKey: key)
    }
}
