import Foundation
import LabcordShared

nonisolated public struct ExperimentListEntry: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let createdAt: Date
    public let status: Status

    public init(id: UUID, title: String, createdAt: Date, status: Status) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.status = status
    }

    public enum Status: String, Equatable, Sendable {
        case preparing
        case inProgress
        case paused
        case completed

        public init(_ status: ExperimentStatus) {
            switch status {
            case .preparing: self = .preparing
            case .inProgress: self = .inProgress
            case .paused: self = .paused
            case .completed: self = .completed
            }
        }
    }

    public var isActive: Bool {
        status == .inProgress || status == .paused
    }

    public static func newestFirst(_ lhs: Self, _ rhs: Self) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
