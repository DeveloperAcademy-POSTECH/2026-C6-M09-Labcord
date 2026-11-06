import CryptoKit
import Foundation

public struct WatchAudioTranscript: Codable, Equatable, Sendable {
    public let header: WatchAudioHeader
    public let throughSample: Int64
    public let revision: UInt64
    public let generationID: UUID
    public let text: String
    public let isFinal: Bool

    public init(
        header: WatchAudioHeader, throughSample: Int64, revision: UInt64,
        generationID: UUID, text: String, isFinal: Bool
    ) {
        self.header = header
        self.throughSample = throughSample
        self.revision = revision
        self.generationID = generationID
        self.text = text
        self.isFinal = isFinal
    }
}

public enum WatchAudioError: String, Error, Codable, Sendable {
    case invalidAudio
    case conflict
    case incomplete
    case storageFull
    case interrupted
    case bufferOverflow
    case permissionDenied
    case recognitionUnavailable
    case storageFailed

    public var watchExperimentError: WatchExperimentError {
        switch self {
        case .permissionDenied: .permissionDenied
        case .conflict: .duplicateConflict
        case .invalidAudio: .invalidPayload
        case .storageFull, .storageFailed: .storageFailed
        case .incomplete, .interrupted, .bufferOverflow, .recognitionUnavailable: .resultUnknown
        }
    }
}

/// PCM signed 16-bit little-endian, mono. Sample positions are recording-relative.
public struct WatchAudioHeader: Codable, Equatable, Sendable {
    public let version: Int
    public let experimentID: UUID
    public let recordingID: UUID
    public let startedAt: Date
    public let sampleRate: Int

    public init(experimentID: UUID, recordingID: UUID, startedAt: Date, sampleRate: Int) {
        version = 1
        self.experimentID = experimentID
        self.recordingID = recordingID
        self.startedAt = startedAt
        self.sampleRate = sampleRate
    }

    public var isValid: Bool { version == 1 && (8_000...192_000).contains(sampleRate) }
}

public struct WatchAudioChunk: Codable, Equatable, Sendable {
    public let header: WatchAudioHeader
    public let sequence: Int
    public let firstSample: Int64
    public let pcm: Data
    public let sha256: String
    public var sampleCount: Int64 { Int64(pcm.count / 2) }

    public init(header: WatchAudioHeader, sequence: Int, firstSample: Int64, pcm: Data) {
        self.header = header
        self.sequence = sequence
        self.firstSample = firstSample
        self.pcm = pcm
        sha256 = Self.digest(pcm)
    }

    public static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public var isValid: Bool {
        header.isValid && sequence >= 0 && sequence < 1_000_000 && firstSample >= 0
            && !pcm.isEmpty && pcm.count <= 131_072 && pcm.count.isMultiple(of: 2)
            && firstSample <= Int64.max - sampleCount && sha256 == Self.digest(pcm)
    }
}

public struct WatchAudioManifest: Codable, Equatable, Sendable {
    public let header: WatchAudioHeader
    public let chunkCount: Int
    public let totalSamples: Int64
    public let interrupted: Bool

    public init(
        header: WatchAudioHeader, chunkCount: Int, totalSamples: Int64, interrupted: Bool = false
    ) {
        self.header = header
        self.chunkCount = chunkCount
        self.totalSamples = totalSamples
        self.interrupted = interrupted
    }
}

public struct WatchAudioReceipt: Codable, Equatable, Sendable {
    public let header: WatchAudioHeader
    public let receivedSequences: [Int]
    public let manifest: WatchAudioManifest?
    /// Set only after both the original file and transcript have been durably saved on iPhone.
    public let savedRecordID: UUID?
    public let isCancelled: Bool
    public let isReviewing: Bool
    public let failure: WatchAudioError?
    public let transcript: WatchAudioTranscript?
    /// 실제 전사 결과와 기존 저장 전사가 다를 때만 설정합니다.
    public let hasTranscriptConflict: Bool?

    public init(
        header: WatchAudioHeader, receivedSequences: [Int], manifest: WatchAudioManifest?,
        savedRecordID: UUID? = nil, isCancelled: Bool = false,
        isReviewing: Bool = false, failure: WatchAudioError? = nil,
        transcript: WatchAudioTranscript? = nil, hasTranscriptConflict: Bool? = nil
    ) {
        self.header = header
        self.receivedSequences = receivedSequences
        self.manifest = manifest
        self.savedRecordID = savedRecordID
        self.isCancelled = isCancelled
        self.isReviewing = isReviewing
        self.failure = failure
        self.transcript = transcript
        self.hasTranscriptConflict = hasTranscriptConflict
    }
}

public enum WatchAudioMessage: Codable, Equatable, Sendable {
    case chunk(WatchAudioChunk)
    case finish(WatchAudioManifest)
    case status(WatchAudioHeader)
    case confirm(WatchAudioHeader)
    case cancel(WatchAudioHeader)
}
