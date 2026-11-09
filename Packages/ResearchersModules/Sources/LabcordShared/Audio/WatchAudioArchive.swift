import CryptoKit
import Foundation

public actor WatchAudioArchive {
    private let root: URL
    private let maximumBytes: Int
    private let files = FileManager.default

    public init(root: URL, maximumBytes: Int = 256 * 1_024 * 1_024) {
        self.root = root
        self.maximumBytes = maximumBytes
    }

    public func begin(_ header: WatchAudioHeader) throws {
        guard header.isValid else { throw WatchAudioError.invalidAudio }
        let url = directory(header).appendingPathComponent("header.json")
        if files.fileExists(atPath: url.path) {
            guard try read(WatchAudioHeader.self, at: url) == header else {
                throw WatchAudioError.conflict
            }
            return
        }
        try write(header, to: url)
    }

    public func accept(_ chunk: WatchAudioChunk) throws -> WatchAudioReceipt {
        guard chunk.isValid else { throw WatchAudioError.invalidAudio }
        try begin(chunk.header)
        let url = chunkURL(chunk.header, sequence: chunk.sequence)
        if files.fileExists(atPath: url.path) {
            guard try read(WatchAudioChunk.self, at: url) == chunk else {
                throw WatchAudioError.conflict
            }
        } else {
            let receipt = try statusEnsuringArchive(chunk.header)
            guard receipt.savedRecordID == nil, !receipt.isCancelled else {
                throw WatchAudioError.conflict
            }
            if let manifest = receipt.manifest {
                guard chunk.sequence < manifest.chunkCount,
                      chunk.firstSample + chunk.sampleCount <= manifest.totalSamples else {
                    throw WatchAudioError.conflict
                }
            }
            for sequence in receipt.receivedSequences {
                let other = try self.chunk(chunk.header, sequence)
                let overlaps = chunk.firstSample < other.firstSample + other.sampleCount
                    && other.firstSample < chunk.firstSample + chunk.sampleCount
                guard !overlaps else { throw WatchAudioError.conflict }
            }
            try write(chunk, to: url)
        }
        return try statusEnsuringArchive(chunk.header)
    }

    public func finish(_ manifest: WatchAudioManifest) throws -> WatchAudioReceipt {
        guard manifest.header.isValid, manifest.chunkCount > 0,
              manifest.chunkCount < 1_000_000, manifest.totalSamples > 0 else {
            throw WatchAudioError.invalidAudio
        }
        try begin(manifest.header)
        let url = directory(manifest.header).appendingPathComponent("manifest.json")
        if files.fileExists(atPath: url.path) {
            guard try read(WatchAudioManifest.self, at: url) == manifest else {
                throw WatchAudioError.conflict
            }
        } else {
            let receipt = try statusEnsuringArchive(manifest.header)
            for sequence in receipt.receivedSequences {
                let chunk = try self.chunk(manifest.header, sequence)
                guard sequence < manifest.chunkCount,
                      chunk.firstSample + chunk.sampleCount <= manifest.totalSamples else {
                    throw WatchAudioError.conflict
                }
            }
            try write(manifest, to: url)
        }
        return try statusEnsuringArchive(manifest.header)
    }

    public func statusEnsuringArchive(_ header: WatchAudioHeader) throws -> WatchAudioReceipt {
        try begin(header)
        let directory = directory(header)
        var sequences = try files.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )
            .filter { $0.pathExtension == "chunk" }
            .compactMap { Int($0.deletingPathExtension().lastPathComponent) }.sorted()
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

    public func chunk(_ header: WatchAudioHeader, _ sequence: Int) throws -> WatchAudioChunk {
        guard sequence >= 0 else { throw WatchAudioError.invalidAudio }
        let chunk = try read(WatchAudioChunk.self, at: chunkURL(header, sequence: sequence))
        guard chunk.header == header, chunk.sequence == sequence, chunk.isValid else {
            throw WatchAudioError.invalidAudio
        }
        return chunk
    }

    public func retainedChunkURL(_ header: WatchAudioHeader, sequence: Int) throws -> URL {
        _ = try chunk(header, sequence)
        return chunkURL(header, sequence: sequence)
    }

    public func rememberRemoteReceipt(_ receipt: WatchAudioReceipt) throws {
        try begin(receipt.header)
        if let proof = try loadOrMigrateCleanupProof(receipt.header) {
            guard receipt.savedRecordID == receipt.header.recordingID,
                  receipt.header == proof.header, receipt.manifest == proof.manifest,
                  receipt.contentDigest == proof.digest, !receipt.isCancelled else {
                throw WatchAudioError.conflict
            }
            return
        }
        let local = try statusEnsuringArchive(receipt.header)
        guard Set(receipt.receivedSequences).isSubset(of: Set(local.receivedSequences)) else {
            throw WatchAudioError.conflict
        }
        try write(receipt, to: directory(receipt.header).appendingPathComponent("remote.json"))
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

    public func markSaved(_ header: WatchAudioHeader, recordID: UUID) throws -> WatchAudioReceipt {
        guard recordID == header.recordingID else { throw WatchAudioError.conflict }
        guard try !statusEnsuringArchive(header).isCancelled else {
            throw WatchAudioError.conflict
        }
        let manifest = try completeManifest(header)
        let digest = try contentDigest(header, manifest: manifest)
        try write(digest, to: directory(header).appendingPathComponent("saved-digest.json"))
        try write(recordID, to: directory(header).appendingPathComponent("saved.json"))
        return try statusEnsuringArchive(header)
    }

    public func cancel(_ header: WatchAudioHeader) throws -> WatchAudioReceipt {
        guard try statusEnsuringArchive(header).savedRecordID == nil else {
            throw WatchAudioError.conflict
        }
        try write(true, to: directory(header).appendingPathComponent("cancelled.json"))
        return try statusEnsuringArchive(header)
    }

    public func acknowledgeSavedAndCleanUp(_ receipt: WatchAudioReceipt) throws {
        guard receipt.savedRecordID == receipt.header.recordingID,
              !receipt.isCancelled, receipt.failure == nil else {
            throw WatchAudioError.incomplete
        }
        let proof: WatchAudioCleanupProof
        if let existing = try loadOrMigrateCleanupProof(receipt.header) {
            guard existing.header == receipt.header, receipt.manifest == existing.manifest,
                  receipt.contentDigest == existing.digest else { throw WatchAudioError.conflict }
            proof = existing
        } else {
            let manifest = try completeManifest(receipt.header)
            let digest = try contentDigest(receipt.header, manifest: manifest)
            guard receipt.manifest == manifest, receipt.contentDigest == digest,
                  receipt.receivedSequences == Array(0..<manifest.chunkCount) else {
                throw WatchAudioError.conflict
            }
            let fingerprints = try (0..<manifest.chunkCount).map { sequence in
                let value = try chunk(receipt.header, sequence)
                return WatchAudioChunkFingerprint(
                    firstSample: value.firstSample, sampleCount: value.sampleCount,
                    sha256: value.sha256
                )
            }
            proof = WatchAudioCleanupProof(
                header: receipt.header, manifest: manifest, digest: digest, chunks: fingerprints
            )

            let proofURL = directory(receipt.header).appendingPathComponent("cleanup-proof.json")
            try write(proof, to: proofURL)
        }
        let local = try statusEnsuringArchive(receipt.header)
        guard local.savedRecordID == nil
            || local.savedRecordID == receipt.header.recordingID else {
            throw WatchAudioError.conflict
        }
        if local.savedRecordID == nil || local.contentDigest != proof.digest {
            _ = try markSaved(receipt.header, recordID: receipt.header.recordingID)
        }
        try resumeSavedCleanup(receipt.header)
    }

    private func directory(_ header: WatchAudioHeader) -> URL {
        root.appendingPathComponent(header.recordingID.uuidString, isDirectory: true)
    }

    private func chunkURL(_ header: WatchAudioHeader, sequence: Int) -> URL {
        directory(header).appendingPathComponent("\(sequence).chunk")
    }

    private func read<Value: Decodable>(_ type: Value.Type, at url: URL) throws -> Value {
        try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }

    private func write<Value: Encodable>(_ value: Value, to url: URL) throws {
        let data = try JSONEncoder().encode(value)
        let existingSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        var used = 0
        if let enumerator = files.enumerator(
            at: root, includingPropertiesForKeys: [.fileSizeKey]
        ) {
            for case let file as URL in enumerator {
                used += (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            }
        }

        let reserve = url.pathExtension == "chunk" ? min(2 * 1_024 * 1_024, maximumBytes / 4) : 0
        guard data.count <= maximumBytes - reserve,
              used - existingSize <= maximumBytes - reserve - data.count else {
            throw WatchAudioError.storageFull
        }
        try files.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(
            to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }
}

extension WatchAudioArchive {

    public func localRetention(_ header: WatchAudioHeader) throws -> WatchAudioLocalRetention {
        try WatchAudioLocalRetentionInspector.inspect(root: root, header: header)
    }

    public func headers() throws -> [WatchAudioHeader] {
        try scanHeaders().headers
    }

    public func scanHeaders() throws -> WatchAudioHeaderScan {
        guard files.fileExists(atPath: root.path) else {
            return WatchAudioHeaderScan(headers: [], damagedRecordingIDs: [])
        }
        let directories = try files.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        var valid: [WatchAudioHeader] = []
        var damaged: [UUID] = []
        for directory in directories {
            guard let id = UUID(uuidString: directory.lastPathComponent) else { continue }
            let url = directory.appendingPathComponent("header.json")
            guard let header = try? read(WatchAudioHeader.self, at: url),
                  header.isValid, header.recordingID == id else {
                damaged.append(id)
                continue
            }
            valid.append(header)
        }
        return WatchAudioHeaderScan(
            headers: valid, damagedRecordingIDs: damaged.sorted { $0.uuidString < $1.uuidString }
        )
    }

    public func completeManifest(_ header: WatchAudioHeader) throws -> WatchAudioManifest {
        let receipt = try statusEnsuringArchive(header)
        if receipt.savedRecordID == header.recordingID,
           let proof = try loadOrMigrateCleanupProof(header) {
            guard receipt.manifest == proof.manifest, receipt.contentDigest == proof.digest else {
                throw WatchAudioError.conflict
            }
            return proof.manifest
        }
        guard let manifest = receipt.manifest,
              receipt.receivedSequences == Array(0..<manifest.chunkCount) else {
            throw WatchAudioError.incomplete
        }
        var expectedSample: Int64 = 0
        for sequence in receipt.receivedSequences {
            let chunk = try chunk(header, sequence)
            guard chunk.firstSample == expectedSample else { throw WatchAudioError.conflict }
            expectedSample += chunk.sampleCount
        }
        guard expectedSample == manifest.totalSamples else { throw WatchAudioError.conflict }
        return manifest
    }

    public func needsSavedCleanup(_ header: WatchAudioHeader) throws -> Bool {
        let receipt = try statusEnsuringArchive(header)
        guard receipt.savedRecordID == header.recordingID else { return false }
        let urls = try files.contentsOfDirectory(
            at: directory(header), includingPropertiesForKeys: nil
        )
        return urls.contains { $0.pathExtension == "chunk" }
    }

    func resumeSavedCleanup(_ header: WatchAudioHeader) throws {
        guard let proof = try loadOrMigrateCleanupProof(header) else { return }
        let local = try statusEnsuringArchive(header)
        guard local.savedRecordID == header.recordingID, local.contentDigest == proof.digest,
              local.manifest == proof.manifest else { throw WatchAudioError.conflict }
        try removeVerifiedChunks(proof)
    }

    private func loadOrMigrateCleanupProof(
        _ header: WatchAudioHeader
    ) throws -> WatchAudioCleanupProof? {
        try begin(header)
        let url = directory(header).appendingPathComponent("cleanup-proof.json")
        guard files.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        if let proof = try? JSONDecoder().decode(WatchAudioCleanupProof.self, from: data) {
            guard proof.header == header else { throw WatchAudioError.conflict }
            return proof
        }
        let upgraded = try WatchAudioLegacyProofMigration.upgrade(
            data: data, header: header
        ) { sequence in
            guard files.fileExists(atPath: chunkURL(header, sequence: sequence).path) else {
                throw WatchAudioError.incomplete
            }
            return try chunk(header, sequence)
        }
        try write(upgraded, to: url)
        return upgraded
    }

    private func removeVerifiedChunks(_ proof: WatchAudioCleanupProof) throws {
        guard proof.chunks.count == proof.manifest.chunkCount else {
            throw WatchAudioError.conflict
        }

        var retained: [URL] = []
        for sequence in 0..<proof.manifest.chunkCount {
            let url = chunkURL(proof.header, sequence: sequence)
            guard files.fileExists(atPath: url.path) else { continue }
            let value = try chunk(proof.header, sequence)
            let expected = proof.chunks[sequence]
            guard value.firstSample == expected.firstSample,
                  value.sampleCount == expected.sampleCount,
                  value.sha256 == expected.sha256 else { throw WatchAudioError.conflict }
            retained.append(url)
        }
        for url in retained { try files.removeItem(at: url) }
    }

    private func contentDigest(
        _ header: WatchAudioHeader, manifest: WatchAudioManifest
    ) throws -> String {
        var hasher = SHA256()
        for sequence in 0..<manifest.chunkCount {
            hasher.update(data: try chunk(header, sequence).pcm)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

}
