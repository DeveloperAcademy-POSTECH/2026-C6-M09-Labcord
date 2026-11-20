import Foundation

extension WatchAudioArchive {
    public func statusIfPresent(_ header: WatchAudioHeader) throws -> WatchAudioReceipt {
        guard header.isValid else { throw WatchAudioError.invalidAudio }
        let url = directory(header).appendingPathComponent("header.json")
        guard files.fileExists(atPath: url.path) else {
            return WatchAudioReceipt(header: header, receivedSequences: [], manifest: nil)
        }
        return try statusEnsuringArchive(header)
    }

    public func confirm(_ header: WatchAudioHeader) throws {
        let receipt = try statusEnsuringArchive(header)
        guard !receipt.isCancelled, receipt.savedRecordID == nil else { return }
        let url = directory(header).appendingPathComponent("confirmed.json")
        if !files.fileExists(atPath: url.path) { try write(true, to: url) }
    }

    public func isConfirmed(_ header: WatchAudioHeader) -> Bool {
        files.fileExists(atPath: directory(header).appendingPathComponent("confirmed.json").path)
    }

    public func remoteReceipt(_ header: WatchAudioHeader) throws -> WatchAudioReceipt? {
        let url = directory(header).appendingPathComponent("remote.json")
        guard files.fileExists(atPath: url.path) else { return nil }
        return try read(WatchAudioReceipt.self, at: url)
    }

    public func sealInterrupted(_ header: WatchAudioHeader) throws -> WatchAudioReceipt {
        let receipt = try statusEnsuringArchive(header)
        guard receipt.manifest == nil else { return receipt }
        guard !receipt.receivedSequences.isEmpty else { throw WatchAudioError.incomplete }
        var sample: Int64 = 0
        for (expected, sequence) in receipt.receivedSequences.enumerated() {
            let chunk = try chunk(header, sequence)
            guard sequence == expected, chunk.firstSample == sample else {
                throw WatchAudioError.incomplete
            }
            sample += chunk.sampleCount
        }
        return try finish(WatchAudioManifest(
            header: header, chunkCount: receipt.receivedSequences.count,
            totalSamples: sample, interrupted: true
        ))
    }
}
