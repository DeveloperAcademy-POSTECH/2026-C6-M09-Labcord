import Foundation

public struct ExperimentTimerCollection: Equatable, Sendable {
    public static let maximumCount = 5

    public private(set) var timers: [ExperimentTimer]
    public private(set) var currentTime: Date

    public var canStartTimer: Bool { timers.count < Self.maximumCount }
    public var hasRunningTimers: Bool { timers.contains { $0.status == .running } }

    public var sortedTimers: [ExperimentTimer] {
        timers.sorted { left, right in
            let leftRemaining = left.remainingSeconds(at: currentTime)
            let rightRemaining = right.remainingSeconds(at: currentTime)
            if leftRemaining != rightRemaining { return leftRemaining < rightRemaining }
            if left.startedAt != right.startedAt { return left.startedAt < right.startedAt }
            return left.id.uuidString < right.id.uuidString
        }
    }

    public init(timers: [ExperimentTimer] = [], currentTime: Date = .now) {
        self.timers = timers
        self.currentTime = currentTime
    }

    @discardableResult
    public mutating func start(durationSeconds: Int, at date: Date) -> Bool {
        advance(to: date)
        guard durationSeconds > 0, canStartTimer else { return false }
        timers.append(ExperimentTimer(durationSeconds: durationSeconds, startedAt: date))
        return true
    }

    @discardableResult
    public mutating func pause(id: UUID, at date: Date) -> Bool {
        advance(to: date)
        guard let index = timers.firstIndex(where: { $0.id == id }),
              timers[index].status == .running else { return false }
        timers[index].pause(at: date)
        return timers[index].status == .paused
    }

    @discardableResult
    public mutating func resume(id: UUID, at date: Date) -> Bool {
        advance(to: date)
        guard let index = timers.firstIndex(where: { $0.id == id }),
              timers[index].status == .paused else { return false }
        timers[index].resume(at: date)
        return true
    }

    @discardableResult
    public mutating func delete(id: UUID) -> Bool {
        guard let index = timers.firstIndex(where: { $0.id == id }),
              timers[index].status != .running else { return false }
        timers.remove(at: index)
        return true
    }

    public mutating func advance(to date: Date) {
        currentTime = date
        for index in timers.indices {
            timers[index].finishIfNeeded(at: date)
        }
    }
}
