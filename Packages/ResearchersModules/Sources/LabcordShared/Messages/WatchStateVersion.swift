import Foundation

public struct WatchStateEpoch: Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public let startedAt: Date

    public init(id: UUID = UUID(), startedAt: Date = .now) {
        self.id = id
        self.startedAt = startedAt
    }

    public func isNewer(than other: Self) -> Bool {
        id != other.id && startedAt > other.startedAt
    }
}

public struct WatchStateVersion: Codable, Equatable, Sendable {
    public let epoch: WatchStateEpoch
    public let revision: UInt64

    public init(epoch: WatchStateEpoch, revision: UInt64) {
        self.epoch = epoch
        self.revision = revision
    }

    public func isNewer(than other: Self) -> Bool {
        epoch == other.epoch ? revision > other.revision : epoch.isNewer(than: other.epoch)
    }
}
