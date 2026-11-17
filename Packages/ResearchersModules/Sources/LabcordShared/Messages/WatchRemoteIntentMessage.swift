import Foundation

public struct WatchRemoteIntentRequest: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case voice, photo, video
    }

    public static let messageKey = "labcordRemoteIntent"
    public let requestID: UUID
    public let experimentID: UUID
    public let expiresAt: Date
    public let kind: Kind

    public init(requestID: UUID, experimentID: UUID, expiresAt: Date, kind: Kind) {
        self.requestID = requestID
        self.experimentID = experimentID
        self.expiresAt = expiresAt
        self.kind = kind
    }

    /// `kind`가 없던 이전 버전 요청은 음성 요청으로 해석합니다.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        requestID = try container.decode(UUID.self, forKey: .requestID)
        experimentID = try container.decode(UUID.self, forKey: .experimentID)
        expiresAt = try container.decode(Date.self, forKey: .expiresAt)
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
