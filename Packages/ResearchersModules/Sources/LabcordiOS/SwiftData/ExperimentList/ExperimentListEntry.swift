import Foundation
import LabcordShared

nonisolated public struct ExperimentListEntry: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let createdAt: Date
    public let status: Status
    public let lastRunningTimerEndsAt: Date?

    public init(
        id: UUID,
        title: String,
        createdAt: Date,
        status: Status,
        lastRunningTimerEndsAt: Date?
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.status = status
        self.lastRunningTimerEndsAt = lastRunningTimerEndsAt
    }

    public enum Status: String, Equatable, Sendable {
        case ready
        case paused
        case completed

        public init(_ status: ExperimentStatus) {
            switch status {
            case .ready: self = .ready
            case .running: self = .paused
            case .paused: self = .paused
            case .completed: self = .completed
            }
        }
    }

    public var isActive: Bool {
        status == .paused
    }

    public static func newestFirst(_ lhs: Self, _ rhs: Self) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
