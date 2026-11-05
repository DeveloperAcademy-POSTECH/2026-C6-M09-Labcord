import Foundation

public struct WatchAudioHeader: Equatable, Sendable {
  public let experimentID: UUID
  public let recordingID: UUID
  public init(experimentID: UUID, recordingID: UUID) {
    self.experimentID = experimentID
    self.recordingID = recordingID
  }
}
public enum WatchAudioError: Error { case conflict, incomplete, interrupted }
public struct WatchAudioReceipt: Sendable {
  public let header: WatchAudioHeader
  public init(header: WatchAudioHeader) { self.header = header }
}
public struct WatchRecordSnapshot: Sendable {
  public enum Kind: Sendable { case audio, other }
  public var kind: Kind = .other
  public var experimentID: UUID?
}
public struct ArchiveStatus {
  public var receivedSequences: [Int] = []
  public var manifest: Manifest?
  public var savedRecordID: UUID?
  public var isCancelled = false
  public struct Manifest { public var totalSamples: Int = 0 }
}
@MainActor public final class WatchAudioArchive {
  public var items: [WatchAudioHeader] = []
  public var saved: Set<UUID> = []
  public var manifests: [UUID] = []
  public init(root: URL) {}
  public func headers() async throws -> [WatchAudioHeader] { items }
  public func status(_ header: WatchAudioHeader) async throws -> ArchiveStatus {
    var status = ArchiveStatus()
    if saved.contains(header.recordingID) { status.savedRecordID = header.recordingID }
    return status
  }
  public func completeManifest(_ header: WatchAudioHeader) async throws -> Int {
    manifests.append(header.recordingID)
    return 0
  }
}
