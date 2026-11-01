import Foundation

public struct ExperimentTimer: Equatable, Identifiable, Sendable {
    public enum Status: Equatable, Sendable {
        case running
        case paused
        case finished
    }

    public struct PauseInterval: Equatable, Sendable {
        public let id: UUID
        public let pausedAt: Date
        public let resumedAt: Date?

        public init(id: UUID = UUID(), pausedAt: Date, resumedAt: Date? = nil) {
            self.id = id
            self.pausedAt = pausedAt
            self.resumedAt = resumedAt
        }
    }

    public let id: UUID
    public let durationSeconds: Int
    public let startedAt: Date
    public private(set) var pauseIntervals: [PauseInterval] = []
    public private(set) var finishedAt: Date?

    public var status: Status {
        if finishedAt != nil { return .finished }
        if pausedAt != nil { return .paused }
        return .running
    }

    private var pausedAt: Date? {
        guard let lastPause = pauseIntervals.last, lastPause.resumedAt == nil else {
            return nil
        }
        return lastPause.pausedAt
    }

    public init(
        id: UUID = UUID(),
        durationSeconds: Int,
        startedAt: Date,
        pauseIntervals: [PauseInterval] = [],
        finishedAt: Date? = nil
    ) {
        self.id = id
        self.durationSeconds = durationSeconds
        self.startedAt = startedAt
        self.pauseIntervals = pauseIntervals
        self.finishedAt = finishedAt
    }

    public func remainingSeconds(at date: Date) -> Int {
        let effectiveDate = pausedAt ?? finishedAt ?? date
        let pausedDuration = pauseIntervals.reduce(0.0) { total, interval in
            let resumedAt = interval.resumedAt ?? effectiveDate
            let duration = resumedAt.timeIntervalSince(interval.pausedAt)

            return total + max(0, duration)
        }
        let elapsed = max(0, effectiveDate.timeIntervalSince(startedAt) - pausedDuration)
        return max(0, Int(ceil(Double(durationSeconds) - elapsed)))
    }

    public mutating func pause(at date: Date) {
        finishIfNeeded(at: date)
        guard status == .running else { return }
        pauseIntervals.append(PauseInterval(pausedAt: date))
    }

    public mutating func resume(at date: Date) {
        guard let pausedAt, let lastIndex = pauseIntervals.indices.last else { return }
        pauseIntervals[lastIndex] = PauseInterval(
            id: pauseIntervals[lastIndex].id,
            pausedAt: pausedAt,
            resumedAt: max(pausedAt, date)
        )
    }

    public mutating func finishIfNeeded(at date: Date) {
        guard status == .running, remainingSeconds(at: date) == 0 else { return }
        let pausedDuration = pauseIntervals.reduce(0.0) { total, interval in
            total + (interval.resumedAt ?? interval.pausedAt).timeIntervalSince(interval.pausedAt)
        }
        finishedAt = startedAt.addingTimeInterval(TimeInterval(durationSeconds) + pausedDuration)
    }
}
