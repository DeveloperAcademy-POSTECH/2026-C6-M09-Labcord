import Foundation

/// Both devices retain their own copy. Transport completion never removes originals.
public actor WatchAudioArchive {
    private let root: URL
    private let maximumBytes: Int
    private let files = FileManager.default

    public init(root: URL, maximumBytes: Int = 256 * 1_024 * 1_024) {
        self.root = root
        self.maximumBytes = maximumBytes
    }

    public func headers() throws -> [WatchAudioHeader] {
        guard files.fileExists(atPath: root.path) else { return [] }
        return try files.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { UUID(uuidString: $0.lastPathComponent) != nil }
            .filter { files.fileExists(atPath: $0.appendingPathComponent("header.json").path) }
            .map { try read(WatchAudioHeader.self, at: $0.appendingPathComponent("header.json")) }
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
        let url = chunkURL(chunk.header, chunk.sequence)
        if files.fileExists(atPath: url.path) {
            guard try read(WatchAudioChunk.self, at: url) == chunk else {
                throw WatchAudioError.conflict
            }
        } else {
            let receipt = try status(chunk.header)
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
        return try status(chunk.header)
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
            let receipt = try status(manifest.header)
            for sequence in receipt.receivedSequences {
                let chunk = try self.chunk(manifest.header, sequence)
                guard sequence < manifest.chunkCount,
                      chunk.firstSample + chunk.sampleCount <= manifest.totalSamples else {
                    throw WatchAudioError.conflict
                }
            }
            try write(manifest, to: url)
        }
        return try status(manifest.header)
    }

    public func status(_ header: WatchAudioHeader) throws -> WatchAudioReceipt {
        try begin(header)
        let directory = directory(header)
        let sequences = try files.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )
            .filter { $0.pathExtension == "chunk" }
            .compactMap { Int($0.deletingPathExtension().lastPathComponent) }.sorted()
        let manifestURL = directory.appendingPathComponent("manifest.json")
        let savedURL = directory.appendingPathComponent("saved.json")
        return WatchAudioReceipt(
            header: header, receivedSequences: sequences,
            manifest: files.fileExists(atPath: manifestURL.path)
                ? try read(WatchAudioManifest.self, at: manifestURL) : nil,
            savedRecordID: files.fileExists(atPath: savedURL.path)
                ? try read(UUID.self, at: savedURL) : nil,
            isCancelled: files.fileExists(
                atPath: directory.appendingPathComponent("cancelled.json").path
            )
        )
    }

    public func chunk(_ header: WatchAudioHeader, _ sequence: Int) throws -> WatchAudioChunk {
        guard sequence >= 0 else { throw WatchAudioError.invalidAudio }
        let chunk = try read(WatchAudioChunk.self, at: chunkURL(header, sequence))
        guard chunk.header == header, chunk.sequence == sequence, chunk.isValid else {
            throw WatchAudioError.invalidAudio
        }
        return chunk
    }

    public func retainedChunkURL(_ header: WatchAudioHeader, sequence: Int) throws -> URL {
        _ = try chunk(header, sequence)
        return chunkURL(header, sequence)
    }

    public func rememberRemoteReceipt(_ receipt: WatchAudioReceipt) throws {
        try begin(receipt.header)
        let local = try status(receipt.header)
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

    public func completeManifest(_ header: WatchAudioHeader) throws -> WatchAudioManifest {
        let receipt = try status(header)
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

    /// Launch recovery only, before a new capture starts. Never seals a live recording.
    public func sealInterrupted(_ header: WatchAudioHeader) throws -> WatchAudioReceipt {
        let receipt = try status(header)
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
        guard try !status(header).isCancelled else { throw WatchAudioError.conflict }
        _ = try completeManifest(header)
        try write(recordID, to: directory(header).appendingPathComponent("saved.json"))
        return try status(header)
    }

    public func cancel(_ header: WatchAudioHeader) throws -> WatchAudioReceipt {
        guard try status(header).savedRecordID == nil else { throw WatchAudioError.conflict }
        try write(true, to: directory(header).appendingPathComponent("cancelled.json"))
        return try status(header)
    }

    /// Call only with a final iPhone save ACK, never a chunk receipt or transfer completion.
    public func acknowledgeSaved(_ receipt: WatchAudioReceipt) throws {
        let manifest = try completeManifest(receipt.header)
        guard receipt.savedRecordID == receipt.header.recordingID,
              receipt.manifest == manifest,
              receipt.receivedSequences == Array(0..<manifest.chunkCount) else {
            throw WatchAudioError.incomplete
        }
        // Retain a small durable receipt so duplicate save ACKs remain idempotent.
        _ = try markSaved(receipt.header, recordID: receipt.header.recordingID)
        // Original cleanup is deliberately explicit; no automatic retention policy is assumed.
    }

    private func directory(_ header: WatchAudioHeader) -> URL {
        root.appendingPathComponent(header.recordingID.uuidString, isDirectory: true)
    }

    private func chunkURL(_ header: WatchAudioHeader, _ sequence: Int) -> URL {
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
        guard data.count <= maximumBytes, used - existingSize <= maximumBytes - data.count else {
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
