import CryptoKit
import Foundation

public enum WatchAudioLocalRetention: Equatable, Sendable {
    case none
    case partial(chunkCount: Int)
    case complete(chunkCount: Int)
    case damaged
}

private struct RetainedChunkRange {
    let sequence: Int
    let firstSample: Int64
    let sampleCount: Int64
}

private enum InvalidRetainedAudio: Error {
    case damaged
}

enum WatchAudioLocalRetentionInspector {
    static func inspect(root: URL, header: WatchAudioHeader) throws -> WatchAudioLocalRetention {
        let directory = root.appendingPathComponent(
            header.recordingID.uuidString, isDirectory: true
        )
        guard try exists(directory) else { return .none }
        do {
            let headerURL = directory.appendingPathComponent("header.json")
            guard let stored: WatchAudioHeader = read(headerURL),
                  stored == header, stored.isValid else { throw InvalidRetainedAudio.damaged }
            let urls = try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil
            )
            let manifest = try loadManifest(directory: directory, header: header)
            let proof = try loadProof(directory: directory, header: header, manifest: manifest)
            let ranges = try loadRanges(
                urls: urls, header: header, manifest: manifest, proof: proof
            )
            let result = classify(ranges: ranges, manifest: manifest)
            if case .complete = result, let proof,
               !matchesWholeProof(directory: directory, ranges: ranges, proof: proof) {
                return .damaged
            }
            return result
        } catch is InvalidRetainedAudio {
            return .damaged
        }
    }

    private static func loadManifest(
        directory: URL, header: WatchAudioHeader
    ) throws -> WatchAudioManifest? {
        let url = directory.appendingPathComponent("manifest.json")
        guard try exists(url) else { return nil }
        guard let manifest: WatchAudioManifest = read(url), manifest.header == header,
              manifest.chunkCount > 0, manifest.chunkCount < 1_000_000,
              manifest.totalSamples > 0 else { throw InvalidRetainedAudio.damaged }
        return manifest
    }

    private static func loadProof(
        directory: URL, header: WatchAudioHeader, manifest: WatchAudioManifest?
    ) throws -> WatchAudioCleanupProof? {
        let url = directory.appendingPathComponent("cleanup-proof.json")
        guard try exists(url) else { return nil }
        guard let proof: WatchAudioCleanupProof = read(url, maximumBytes: 2 * 1_024 * 1_024),
              proof.header == header, proof.manifest == manifest,
              proof.chunks.count == proof.manifest.chunkCount else {
            throw InvalidRetainedAudio.damaged
        }
        let savedURL = directory.appendingPathComponent("saved.json")
        let digestURL = directory.appendingPathComponent("saved-digest.json")
        if try exists(savedURL) {
            guard let savedID: UUID = read(savedURL), savedID == header.recordingID,
                  let digest: String = read(digestURL), digest == proof.digest else {
                throw InvalidRetainedAudio.damaged
            }
        } else if try exists(digestURL) {
            guard let digest: String = read(digestURL), digest == proof.digest else {
                throw InvalidRetainedAudio.damaged
            }
        }
        return proof
    }

    private static func loadRanges(
        urls: [URL], header: WatchAudioHeader, manifest: WatchAudioManifest?,
        proof: WatchAudioCleanupProof?
    ) throws -> [RetainedChunkRange] {
        var ranges: [RetainedChunkRange] = []
        for url in urls where url.pathExtension == "chunk" {
            guard let sequence = Int(url.deletingPathExtension().lastPathComponent), sequence >= 0,
                  url.lastPathComponent == "\(sequence).chunk",
                  let chunk: WatchAudioChunk = read(url), chunk.isValid,
                  chunk.header == header, chunk.sequence == sequence else {
                throw InvalidRetainedAudio.damaged
            }
            if let manifest {
                guard sequence < manifest.chunkCount,
                      chunk.firstSample + chunk.sampleCount <= manifest.totalSamples else {
                    throw InvalidRetainedAudio.damaged
                }
            }
            if let proof {
                guard sequence < proof.chunks.count else { throw InvalidRetainedAudio.damaged }
                let expected = proof.chunks[sequence]
                guard chunk.firstSample == expected.firstSample,
                      chunk.sampleCount == expected.sampleCount,
                      chunk.sha256 == expected.sha256 else { throw InvalidRetainedAudio.damaged }
            }
            ranges.append(RetainedChunkRange(
                sequence: sequence, firstSample: chunk.firstSample, sampleCount: chunk.sampleCount
            ))
        }
        return ranges.sorted { $0.sequence < $1.sequence }
    }

    private static func classify(
        ranges: [RetainedChunkRange], manifest: WatchAudioManifest?
    ) -> WatchAudioLocalRetention {
        guard !ranges.isEmpty else { return .none }
        var previousEnd: Int64 = 0
        var previousSequence = -1
        for range in ranges {
            let missing = Int64(range.sequence - previousSequence - 1)
            guard range.firstSample >= previousEnd,
                  range.firstSample - previousEnd >= missing else { return .damaged }
            if missing == 0, range.firstSample != previousEnd { return .damaged }
            previousEnd = range.firstSample + range.sampleCount
            previousSequence = range.sequence
        }
        guard let manifest, ranges.count == manifest.chunkCount,
              ranges.enumerated().allSatisfy({ $0.offset == $0.element.sequence }) else {
            return .partial(chunkCount: ranges.count)
        }
        guard previousEnd == manifest.totalSamples else { return .damaged }
        return .complete(chunkCount: ranges.count)
    }

    private static func matchesWholeProof(
        directory: URL, ranges: [RetainedChunkRange], proof: WatchAudioCleanupProof
    ) -> Bool {
        var hasher = SHA256()
        for range in ranges {
            let url = directory.appendingPathComponent("\(range.sequence).chunk")
            guard let chunk: WatchAudioChunk = read(url), chunk.isValid,
                  chunk.header == proof.header, chunk.sequence == range.sequence,
                  chunk.firstSample == range.firstSample, chunk.sampleCount == range.sampleCount,
                  chunk.sha256 == proof.chunks[range.sequence].sha256 else { return false }
            hasher.update(data: chunk.pcm)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return digest == proof.digest
    }

    private static func exists(_ url: URL) throws -> Bool {
        do {
            _ = try url.resourceValues(forKeys: [.isDirectoryKey])
            return true
        } catch let error as CocoaError where error.code == .fileNoSuchFile
            || error.code == .fileReadNoSuchFile {
            return false
        }
    }

    private static func read<Value: Decodable>(
        _ url: URL, maximumBytes: Int = 200_000
    ) -> Value? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > 0, size <= maximumBytes,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }
}
