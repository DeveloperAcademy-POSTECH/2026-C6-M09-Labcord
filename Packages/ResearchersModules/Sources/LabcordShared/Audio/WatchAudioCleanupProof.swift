import CryptoKit
import Foundation

struct WatchAudioChunkFingerprint: Codable, Equatable, Sendable {
    let firstSample: Int64
    let sampleCount: Int64
    let sha256: String
}

struct WatchAudioCleanupProof: Codable, Equatable, Sendable {
    let header: WatchAudioHeader
    let manifest: WatchAudioManifest
    let digest: String
    let chunks: [WatchAudioChunkFingerprint]
}

private struct LegacyWatchAudioCleanupProof: Decodable {
    let header: WatchAudioHeader
    let manifest: WatchAudioManifest
    let digest: String
}

enum WatchAudioLegacyProofMigration {
    static func upgrade(
        data: Data, header: WatchAudioHeader, readChunk: (Int) throws -> WatchAudioChunk
    ) throws -> WatchAudioCleanupProof {
        guard let legacy = try? JSONDecoder().decode(
            LegacyWatchAudioCleanupProof.self, from: data
        ),
              legacy.header == header, legacy.manifest.header == header,
              legacy.manifest.chunkCount > 0, legacy.manifest.chunkCount < 1_000_000 else {
            throw WatchAudioError.conflict
        }

        var samples: Int64 = 0
        var fingerprints: [WatchAudioChunkFingerprint] = []
        var hasher = SHA256()
        for sequence in 0..<legacy.manifest.chunkCount {
            let value = try readChunk(sequence)
            guard value.header == header, value.sequence == sequence, value.isValid,
                  value.firstSample == samples else { throw WatchAudioError.conflict }
            samples += value.sampleCount
            hasher.update(data: value.pcm)
            fingerprints.append(WatchAudioChunkFingerprint(
                firstSample: value.firstSample, sampleCount: value.sampleCount,
                sha256: value.sha256
            ))
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard samples == legacy.manifest.totalSamples, digest == legacy.digest else {
            throw WatchAudioError.conflict
        }
        return WatchAudioCleanupProof(
            header: header, manifest: legacy.manifest, digest: digest, chunks: fingerprints
        )
    }
}
