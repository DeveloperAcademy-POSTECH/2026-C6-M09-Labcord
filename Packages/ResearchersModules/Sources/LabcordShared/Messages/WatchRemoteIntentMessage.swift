import Foundation

public struct WatchRemoteIntentRequest: Codable, Sendable, Equatable {
    public static let messageKey = "labcordRemoteIntent"
    public let requestID: UUID
    public let experimentID: UUID
    public let expiresAt: Date

    public init(requestID: UUID, experimentID: UUID, expiresAt: Date) {
        self.requestID = requestID
        self.experimentID = experimentID
        self.expiresAt = expiresAt
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
