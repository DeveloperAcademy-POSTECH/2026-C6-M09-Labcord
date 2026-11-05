import Foundation

public struct WatchExperimentSummary: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let status: ExperimentStatus

    public init(id: UUID, title: String, status: ExperimentStatus) {
        self.id = id
        self.title = title
        self.status = status
    }
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

    public init(
        id: UUID, durationSeconds: Int, remainingSeconds: Int, status: Status, measuredAt: Date
    ) {
        self.id = id
        self.durationSeconds = durationSeconds
        self.remainingSeconds = remainingSeconds
        self.status = status
        self.measuredAt = measuredAt
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
    /// iPhone에서 해당 실험 진행 화면이 현재 활성 상태인지 나타낸다.
    public let phoneSessionActive: Bool?

    public init(
        experiment: WatchExperimentSummary,
        revision: UInt64,
        protocolTimerSeconds: [Int] = [],
        timers: [WatchTimerSnapshot] = [],
        recordedAt: Date = .now,
        mode: ExperimentMode? = nil,
        phoneSessionActive: Bool? = nil
    ) {
        self.experiment = experiment
        self.revision = revision
        self.mode = mode
        self.protocolTimerSeconds = protocolTimerSeconds
        self.timers = timers
        self.recordedAt = recordedAt
        self.phoneSessionActive = phoneSessionActive
    }
}
