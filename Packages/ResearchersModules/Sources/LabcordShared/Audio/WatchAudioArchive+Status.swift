import Foundation

extension WatchAudioArchive {
    public func statusEnsuringArchive(_ header: WatchAudioHeader) throws -> WatchAudioReceipt {
        try begin(header)
        return try archiveStatus(header)
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
