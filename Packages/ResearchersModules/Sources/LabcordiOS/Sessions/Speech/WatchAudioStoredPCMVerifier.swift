import AVFoundation
import CryptoKit
import Foundation
import LabcordShared

enum WatchAudioStoredPCMVerifier {
    nonisolated static func verifyDigest(
        _ url: URL, header: WatchAudioHeader, manifest: WatchAudioManifest, expected: String,
        progress: (@Sendable (Int64) -> Void)? = nil
    ) throws {
        guard manifest.header == header else { throw WatchAudioError.conflict }
        let file = try AVAudioFile(
            forReading: url, commonFormat: .pcmFormatInt16, interleaved: false
        )
        let format = file.processingFormat
        guard format.sampleRate == Double(header.sampleRate), format.channelCount == 1,
              file.length == manifest.totalSamples else { throw WatchAudioError.conflict }
        var hasher = SHA256()
        let capacity: AVAudioFrameCount = 16_384
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw WatchAudioError.invalidAudio
        }
        var remaining = manifest.totalSamples
        let clock = ContinuousClock()
        var lastProgress = clock.now
        while remaining > 0 {
            try Task.checkCancellation()
            let count = AVAudioFrameCount(min(remaining, Int64(capacity)))
            try file.read(into: buffer, frameCount: count)
            guard buffer.frameLength == count, let samples = buffer.int16ChannelData?[0] else {
                throw WatchAudioError.conflict
            }
            hasher.update(data: Data(bytes: samples, count: Int(count) * MemoryLayout<Int16>.size))
            remaining -= Int64(count)
            if let progress, remaining == 0
                || lastProgress.duration(to: clock.now) >= .milliseconds(250) {
                progress(manifest.totalSamples - remaining)
                lastProgress = clock.now
            }
        }
        let actual = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == expected else { throw WatchAudioError.conflict }
    }

    static func verifyChunk(_ url: URL, header: WatchAudioHeader, chunk: WatchAudioChunk) throws {
        guard chunk.isValid, chunk.header == header else { throw WatchAudioError.invalidAudio }
        let file = try AVAudioFile(
            forReading: url, commonFormat: .pcmFormatInt16, interleaved: false
        )
        let format = file.processingFormat
        guard format.sampleRate == Double(header.sampleRate), format.channelCount == 1,
              chunk.firstSample + chunk.sampleCount <= file.length else {
            throw WatchAudioError.conflict
        }
        file.framePosition = chunk.firstSample
        let frameCount = AVAudioFrameCount(chunk.sampleCount)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: frameCount
        ) else { throw WatchAudioError.invalidAudio }
        try file.read(into: buffer, frameCount: frameCount)
        guard buffer.frameLength == frameCount, let samples = buffer.int16ChannelData?[0],
              Data(bytes: samples, count: chunk.pcm.count) == chunk.pcm else {
            throw WatchAudioError.conflict
        }
    }

    static func verify(
        _ url: URL, header: WatchAudioHeader, archive: WatchAudioArchive
    ) async throws {
        let manifest = try await archive.completeManifest(header)
        let file = try AVAudioFile(
            forReading: url, commonFormat: .pcmFormatInt16, interleaved: false
        )
        let format = file.processingFormat
        guard format.sampleRate == Double(header.sampleRate), format.channelCount == 1,
              file.length == manifest.totalSamples else { throw WatchAudioError.conflict }
        for sequence in 0..<manifest.chunkCount {
            try Task.checkCancellation()
            let chunk = try await archive.chunk(header, sequence)
            let frameCount = AVAudioFrameCount(chunk.sampleCount)
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: format, frameCapacity: frameCount
            ) else {
                throw WatchAudioError.invalidAudio
            }
            try file.read(into: buffer, frameCount: frameCount)
            guard buffer.frameLength == frameCount, let samples = buffer.int16ChannelData?[0],
                  Data(bytes: samples, count: chunk.pcm.count) == chunk.pcm else {
                throw WatchAudioError.conflict
            }
        }
    }
}
