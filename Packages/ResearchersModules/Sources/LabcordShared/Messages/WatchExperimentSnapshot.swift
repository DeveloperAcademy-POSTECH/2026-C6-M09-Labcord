import Foundation

public struct WatchExperimentSummary: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let status: ExperimentStatus

    public init(id: UUID, title: String, status: ExperimentStatus) {
        self.id = id
        self.title = title
        self.status = status
    }
}

public struct WatchExperimentList: Equatable, Sendable {
    public let experiments: [WatchExperimentSummary]
    public let version: WatchStateVersion?

    public init(experiments: [WatchExperimentSummary], version: WatchStateVersion? = nil) {
        self.experiments = experiments
        self.version = version
    }
}

public enum WatchExperimentListUpdate: Sendable {
    case snapshot(WatchExperimentList)
    case invalidated(WatchStateEpoch)
}

public struct WatchTimerSnapshot: Codable, Equatable, Identifiable, Sendable {
    public enum Status: String, Codable, Sendable {
        case running
        case paused
        case finished
    }

    public let id: UUID
    public let durationSeconds: Int
    public let remainingSeconds: Int
    public let status: Status
    public let measuredAt: Date
    public let startedAt: Date?

    public init(
        id: UUID, durationSeconds: Int, remainingSeconds: Int, status: Status,
        measuredAt: Date, startedAt: Date? = nil
    ) {
        self.id = id
        self.durationSeconds = durationSeconds
        self.remainingSeconds = remainingSeconds
        self.status = status
        self.measuredAt = measuredAt
        self.startedAt = startedAt
    }

    public func remaining(at date: Date) -> Int {
        guard status == .running else { return max(0, remainingSeconds) }
        let elapsed = max(0, date.timeIntervalSince(measuredAt))
        let remaining = max(0, Double(remainingSeconds) - elapsed)
        guard remaining < Double(Int.max) else { return Int.max }
        return Int(ceil(remaining))
    }
}

public struct WatchExperimentSnapshot: Codable, Equatable, Sendable {
    public let experiment: WatchExperimentSummary
    public let revision: UInt64
    public let mode: ExperimentMode?
    public let protocolTimerSeconds: [Int]
    public let timers: [WatchTimerSnapshot]
    public let recordedAt: Date

    public let phoneSessionActive: Bool?
    public let epoch: WatchStateEpoch?

    public init(
        experiment: WatchExperimentSummary,
        revision: UInt64,
        protocolTimerSeconds: [Int] = [],
        timers: [WatchTimerSnapshot] = [],
        recordedAt: Date = .now,
        mode: ExperimentMode? = nil,
        phoneSessionActive: Bool? = nil,
        epoch: WatchStateEpoch? = nil
    ) {
        self.experiment = experiment
        self.revision = revision
        self.mode = mode
        self.protocolTimerSeconds = protocolTimerSeconds
        self.timers = timers
        self.recordedAt = recordedAt
        self.phoneSessionActive = phoneSessionActive
        self.epoch = epoch
    }

    public func isNewer(than previous: Self) -> Bool {
        if epoch != previous.epoch {
            guard let epoch else { return false }
            return previous.epoch.map { epoch.isNewer(than: $0) } ?? true
        }
        return revision > previous.revision
            || revision == previous.revision && recordedAt > previous.recordedAt
                && hasSameState(as: previous)
    }

    private func hasSameState(as previous: Self) -> Bool {
        guard experiment == previous.experiment, mode == previous.mode,
              phoneSessionActive == previous.phoneSessionActive,
              protocolTimerSeconds == previous.protocolTimerSeconds,
              timers.count == previous.timers.count else { return false }
        return zip(timers, previous.timers).allSatisfy { current, old in
            guard current.id == old.id, current.durationSeconds == old.durationSeconds,
                  current.status == old.status,
                  current.startedAt == old.startedAt else { return false }
            if current.status == .running {
                let end = current.measuredAt.addingTimeInterval(Double(current.remainingSeconds))
                let oldEnd = old.measuredAt.addingTimeInterval(Double(old.remainingSeconds))
                return abs(end.timeIntervalSince(oldEnd)) < 0.000_001
            }
            return current.remainingSeconds == old.remainingSeconds
        }
    }
}
