import Foundation

public struct WatchGesturePracticeRequest: Codable, Sendable {
    public static let messageKey = "gesture.practice.v1"
    public static let lifetime: TimeInterval = 3
    public let requestID: UUID
    public let kind: WatchRemoteIntentRequest.Kind
    public let sentAt: Date

    public init(
        kind: WatchRemoteIntentRequest.Kind, sentAt: Date = .now, requestID: UUID = UUID()
    ) {
        self.requestID = requestID
        self.kind = kind
        self.sentAt = sentAt
    }

    public func isLive(at date: Date) -> Bool {
        date < sentAt.addingTimeInterval(Self.lifetime) && sentAt <= date.addingTimeInterval(1)
    }
}

public struct WatchGestureRouteReply: Codable, Sendable {
    public enum Route: Codable, Sendable {
        case practice
        case experiment(
            WatchScreenSnapshot, screenAge: TimeInterval, summary: WatchExperimentSummary? = nil
        )
    }

    public let requestID: UUID
    public let route: Route

    public init(requestID: UUID, route: Route) {
        self.requestID = requestID
        self.route = route
    }
}

public struct WatchRemoteIntentRequest: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case voice, photo, video
    }

    public static let messageKey = "labcordRemoteIntent"
    public let requestID: UUID
    public let experimentID: UUID
    public let expiresAt: Date
    public let gestureSession: WatchGestureSession?
    public let kind: Kind

    public init(
        requestID: UUID, experimentID: UUID, expiresAt: Date, kind: Kind,
        gestureSession: WatchGestureSession? = nil
    ) {
        self.requestID = requestID
        self.experimentID = experimentID
        self.gestureSession = gestureSession
        self.expiresAt = expiresAt
        self.kind = kind
    }

    /// `kind`가 없던 이전 버전 요청은 음성 요청으로 해석합니다.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        requestID = try container.decode(UUID.self, forKey: .requestID)
        experimentID = try container.decode(UUID.self, forKey: .experimentID)
        expiresAt = try container.decode(Date.self, forKey: .expiresAt)
        gestureSession = try container.decodeIfPresent(
            WatchGestureSession.self, forKey: .gestureSession
        )
        kind = try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .voice
    }
}

public struct WatchRemoteIntentResponse: Codable, Sendable, Equatable {
    public static let messageKey = "labcordRemoteIntentResponse"
    public let requestID: UUID
    public let accepted: Bool
    public let message: String

    public init(requestID: UUID, accepted: Bool, message: String) {
        self.requestID = requestID
        self.accepted = accepted
        self.message = message
    }
}
