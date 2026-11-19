import Foundation

extension WatchAudioArchive {
    public func statusEnsuringArchive(_ header: WatchAudioHeader) throws -> WatchAudioReceipt {
        try begin(header)
        return try archiveStatus(header)
    }

    public func transferSize(for header: WatchAudioHeader) throws -> WatchAudioTransferSize? {
        guard let manifest = try statusIfPresent(header).manifest,
              manifest.header == header, (1..<1_000_000).contains(manifest.chunkCount),
              manifest.totalSamples > 0 else { return nil }
        var counts: [Int64] = []
        var end: Int64 = 0
        for sequence in 0..<manifest.chunkCount {
            try Task.checkCancellation()
            let range = try chunkRange(header, sequence: sequence)
            guard range.firstSample == end, range.endSample > end,
                  range.endSample <= manifest.totalSamples else { return nil }
            counts.append(range.endSample - end)
            end = range.endSample
        }
        guard end == manifest.totalSamples else { return nil }
        return WatchAudioTransferSize(sampleCounts: counts, totalSamples: end)
    }

    func archiveStatus(
        _ header: WatchAudioHeader, sequences knownSequences: [Int]? = nil
    ) throws -> WatchAudioReceipt {
        let directory = directory(header)
        let files = FileManager.default
        var sequences: [Int]
        if let knownSequences {
            sequences = knownSequences
        } else {
            sequences = try files.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil
            )
                .filter { $0.pathExtension == "chunk" }
                .compactMap { Int($0.deletingPathExtension().lastPathComponent) }.sorted()
        }
        let manifestURL = directory.appendingPathComponent("manifest.json")
        let savedURL = directory.appendingPathComponent("saved.json")
        let digestURL = directory.appendingPathComponent("saved-digest.json")
        let manifest = files.fileExists(atPath: manifestURL.path)
            ? try read(WatchAudioManifest.self, at: manifestURL) : nil
        let savedID = files.fileExists(atPath: savedURL.path)
            ? try read(UUID.self, at: savedURL) : nil
        let digest = savedID != nil && files.fileExists(atPath: digestURL.path)
            ? try read(String.self, at: digestURL) : nil
        if savedID == header.recordingID, let proof = try loadOrMigrateCleanupProof(header) {
            guard proof.manifest == manifest, proof.digest == digest else {
                throw WatchAudioError.conflict
            }

            sequences = Array(0..<proof.manifest.chunkCount)
        }
        return WatchAudioReceipt(
            header: header, receivedSequences: sequences,
            manifest: manifest, savedRecordID: savedID, contentDigest: digest,
            isCancelled: files.fileExists(
                atPath: directory.appendingPathComponent("cancelled.json").path
            )
        )
    }
}

public struct WatchAudioTransferSize: Equatable, Sendable {
    fileprivate let sampleCounts: [Int64]
    fileprivate let totalSamples: Int64

    public func percentage(for receivedSequences: [Int]) -> Int {
        let samples = Set(receivedSequences).reduce(Int64(0)) { sum, sequence in
            sum + (sampleCounts.indices.contains(sequence) ? sampleCounts[sequence] : 0)
        }
        return Int(samples * 100 / totalSamples)
    }
}
