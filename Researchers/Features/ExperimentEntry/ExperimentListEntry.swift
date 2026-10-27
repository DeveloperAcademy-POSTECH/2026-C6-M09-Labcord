import Foundation
import LabcordShared

/// 저장 객체를 화면과 비동기 Feature에 직접 전달하지 않는 목록 값입니다.
nonisolated struct ExperimentListEntry: Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let createdAt: Date
    let status: Status

    enum Status: String, Equatable, Sendable {
        case preparing
        case inProgress
        case paused
        case completed

        init(_ status: ExperimentStatus) {
            switch status {
            case .preparing: self = .preparing
            case .inProgress: self = .inProgress
            case .paused: self = .paused
            case .completed: self = .completed
            }
        }
    }

    var isActive: Bool {
        status == .inProgress || status == .paused
    }

    var statusTitle: String {
        switch status {
        case .preparing: "준비"
        case .inProgress: "진행 중"
        case .paused: "일시 정지"
        case .completed: "종료"
        }
    }

    static func newestFirst(_ lhs: Self, _ rhs: Self) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
