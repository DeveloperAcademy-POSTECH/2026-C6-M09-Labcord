import Foundation

public struct WatchSessionOpenRequest: Codable, Equatable, Sendable {
    public enum Action: String, Codable, Sendable {
        case open
        case cancel
        case leftExperiment
        case enteredExperiment
    }

    public nonisolated static let messageKey = "experiment.openSession.v1"
    public nonisolated static let confirmedMessageKey = "experiment.openSession.confirmed.v1"
    public nonisolated static let lifetime: TimeInterval = 20

    public let requestID: UUID
    public let experimentID: UUID
    public let requestedAt: Date
    public let action: Action?
    public let expiresAt: Date?
    public let targetRequestID: UUID?
    public let epoch: WatchStateEpoch?

    public init(
        experimentID: UUID, action: Action = .open, requestID: UUID = UUID(),
        requestedAt: Date = .now, expiresAt: Date? = nil, targetRequestID: UUID? = nil,
        epoch: WatchStateEpoch? = nil
    ) {
        self.requestID = requestID
        self.experimentID = experimentID
        self.requestedAt = requestedAt
        self.action = action
        self.expiresAt = expiresAt
        self.targetRequestID = targetRequestID
        self.epoch = epoch
    }

    public var deadline: Date {
        let limit = requestedAt.addingTimeInterval(Self.lifetime)
        return min(expiresAt ?? limit, limit)
    }

    public func isLive(at date: Date) -> Bool {
        requestedAt <= date.addingTimeInterval(5) && date < deadline
    }

    public func cancellation() -> Self {
        Self(
            experimentID: experimentID, action: .cancel, requestedAt: requestedAt,
            expiresAt: expiresAt, targetRequestID: requestID, epoch: epoch
        )
    }

    public func supersedes(_ previous: Self) -> Bool {
        if action == .cancel {
            guard let targetRequestID else {
                return experimentID == previous.experimentID && requestedAt > previous.requestedAt
            }
            if targetRequestID == previous.requestID {
                return experimentID == previous.experimentID && requestedAt == previous.requestedAt
            }
        }
        return requestedAt > previous.requestedAt
    }
}

public struct WatchSessionOpenResponse: Codable, Sendable {
    public nonisolated static let messageKey = "experiment.openSession.ack.v1"

    public let requestID: UUID
    public let error: WatchExperimentError?

    public init(requestID: UUID, error: WatchExperimentError? = nil) {
        self.requestID = requestID
        self.error = error
    }
}
