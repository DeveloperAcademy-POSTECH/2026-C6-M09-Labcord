import Foundation

public struct WatchAudioHeaderScan: Sendable {
    public let headers: [WatchAudioHeader]
    public let damagedRecordingIDs: [UUID]

    public init(headers: [WatchAudioHeader], damagedRecordingIDs: [UUID]) {
        self.headers = headers
        self.damagedRecordingIDs = damagedRecordingIDs
    }
}
