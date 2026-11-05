import AVFoundation
import Foundation
import LabcordShared
import WatchKit

public enum WatchAudioCaptureEvent: Equatable, Sendable {
    case recording(WatchAudioHeader)
    case retaining(WatchAudioHeader, throughSample: Int64)
    case retained(WatchAudioManifest)
    case failed(WatchAudioError)
}

/// Capture and disk work are independent of transport reachability.
@MainActor
public final class WatchAudioRecorder {
    public let archive: WatchAudioArchive
    public var activeRecording: WatchAudioHeader? { header }
    private let engine = AVAudioEngine()
    private var header: WatchAudioHeader?
    private var continuation: AsyncThrowingStream<Data, Error>.Continuation?
    private var writer: Task<Void, Never>?
    private var interruptions: Task<Void, Never>?
    private var events: AsyncStream<WatchAudioCaptureEvent>.Continuation?
    private var interrupted = false
    private var stopping = false
    private var starting = false
    private var hasTap = false

    public init(archive: WatchAudioArchive) {
        self.archive = archive
    }

    public func start(
        experimentID: UUID, recordingID: UUID = UUID()
    ) async throws -> AsyncStream<WatchAudioCaptureEvent> {
        guard header == nil, writer == nil, !starting else { throw WatchAudioError.conflict }
        starting = true
        defer { starting = false }
        guard WKApplication.shared().applicationState == .active else {
            throw WatchAudioError.interrupted
        }
        let session = AVAudioSession.sharedInstance()
        guard AVAudioApplication.shared.recordPermission == .granted else {
            throw WatchAudioError.permissionDenied
        }
        try session.setCategory(.record, mode: .measurement)
        try session.setActive(true)
        do {
            return try await begin(experimentID: experimentID, recordingID: recordingID)
        } catch {
            try? session.setActive(false)
            throw error
        }
    }

    private func begin(
        experimentID: UUID, recordingID: UUID
    ) async throws -> AsyncStream<WatchAudioCaptureEvent> {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.commonFormat == .pcmFormatFloat32, !format.isInterleaved,
              format.channelCount > 0 else { throw WatchAudioError.invalidAudio }
        let header = WatchAudioHeader(
            experimentID: experimentID, recordingID: recordingID, startedAt: .now,
            sampleRate: Int(format.sampleRate)
        )
        self.header = header
        do {
            try await archive.begin(header)
        } catch {
            self.header = nil
            throw error
        }
        guard self.header == header else { throw CancellationError() }
        try await requireForeground(header)
        interrupted = false
        stopping = false
        let (stream, continuation) = AsyncThrowingStream<Data, Error>.makeStream(
            bufferingPolicy: .bufferingOldest(32)
        )
        self.continuation = continuation
        let (eventStream, eventContinuation) = AsyncStream<WatchAudioCaptureEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(4)
        )
        events = eventContinuation
        installTap(input: input, format: format, continuation: continuation)
        writer = Task { await self.consume(stream, header: header) }
        interruptions = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(
                named: AVAudioSession.interruptionNotification
            ) {
                guard let self, self.header == header else { return }
                self.interrupted = true
                await self.stop()
                return
            }
        }
        do {
            try engine.start()
        } catch {
            interrupted = true
            await stop()
            throw error
        }
        events?.yield(.recording(header))
        return eventStream
    }

    private func requireForeground(_ header: WatchAudioHeader) async throws {
        guard WKApplication.shared().applicationState == .active else {
            self.header = nil
            _ = try await archive.cancel(header)
            throw WatchAudioError.interrupted
        }
    }

    private func installTap(
        input: AVAudioInputNode, format: AVAudioFormat,
        continuation: AsyncThrowingStream<Data, Error>.Continuation
    ) {
        hasTap = true
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { @Sendable buffer, _ in
            // The engine can deliver more frames than the requested tap buffer size.
            guard let samples = buffer.floatChannelData?[0],
                  buffer.frameLength <= buffer.frameCapacity, buffer.frameLength <= 65_536 else {
                continuation.finish(throwing: WatchAudioError.invalidAudio)
                return
            }
            var data = Data(capacity: Int(buffer.frameLength) * 2)
            for index in 0..<Int(buffer.frameLength) {
                let sample = samples[index].isFinite ? samples[index] : 0
                var value = Int16(max(-1, min(1, sample)) * 32767).littleEndian
                withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
            }
            if case .dropped = continuation.yield(data) {
                continuation.finish(throwing: WatchAudioError.bufferOverflow)
            }
        }
    }

    public func stop() async {
        if stopping {
            await writer?.value
            return
        }
        guard header != nil else { return }
        stopping = true
        engine.stop()
        removeTap()
        continuation?.finish()
        continuation = nil
        interruptions?.cancel()
        interruptions = nil
        await writer?.value
        writer = nil
        header = nil
        stopping = false
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    public func stopForExperiment(_ experimentID: UUID) async throws -> [WatchAudioReceipt] {
        let stopped = header
        if let header {
            guard header.experimentID == experimentID else { throw WatchAudioError.conflict }
            await stop()
        }
        if let stopped { _ = try await archive.completeManifest(stopped) }
        var receipts: [WatchAudioReceipt] = []
        for header in try await archive.headers() where header.experimentID == experimentID {
            let receipt = try await archive.status(header)
            if !receipt.receivedSequences.isEmpty {
                _ = try await archive.completeManifest(header)
                receipts.append(receipt)
            }
        }
        return receipts
    }

    public func recoverInterruptedRecordings() async throws {
        guard header == nil, !starting else { throw WatchAudioError.conflict }
        for header in try await archive.headers() {
            try Task.checkCancellation()
            do {
                let receipt = try await archive.status(header)
                if receipt.manifest == nil, !receipt.receivedSequences.isEmpty {
                    _ = try await archive.sealInterrupted(header)
                }
            } catch {
                // Restoration reports this retained record; other recordings can still recover.
                continue
            }
        }
    }

    private func removeTap() {
        guard hasTap else { return }
        engine.inputNode.removeTap(onBus: 0)
        hasTap = false
    }

    private func consume(
        _ stream: AsyncThrowingStream<Data, Error>, header: WatchAudioHeader
    ) async {
        var sequence = 0
        var firstSample: Int64 = 0
        var failure: WatchAudioError?
        var pending = Data()
        do {
            for try await pcm in stream {
                pending.append(pcm)
                while pending.count >= 16_384 {
                    let chunk = WatchAudioChunk(
                        header: header, sequence: sequence, firstSample: firstSample,
                        pcm: Data(pending.prefix(16_384))
                    )
                    _ = try await archive.accept(chunk)
                    pending.removeFirst(16_384)
                    firstSample += chunk.sampleCount
                    sequence += 1
                    events?.yield(.retaining(header, throughSample: firstSample))
                }
            }
            if !pending.isEmpty {
                let chunk = WatchAudioChunk(
                    header: header, sequence: sequence, firstSample: firstSample, pcm: pending
                )
                _ = try await archive.accept(chunk)
                firstSample += chunk.sampleCount
                sequence += 1
            }
        } catch {
            failure = (error as? WatchAudioError) ?? .interrupted
            engine.stop()
            removeTap()
        }
        failure = await seal(
            header, sequence: sequence, firstSample: firstSample, failure: failure
        )
        if let failure { events?.yield(.failed(failure)) }
        events?.finish()
        events = nil
        self.header = nil
        writer = nil
        interruptions?.cancel()
        interruptions = nil
        try? AVAudioSession.sharedInstance().setActive(false)
    }
    private func seal(
        _ header: WatchAudioHeader, sequence: Int, firstSample: Int64, failure: WatchAudioError?
    ) async -> WatchAudioError? {
        var failure = failure
        if sequence > 0 {
            let manifest = WatchAudioManifest(
                header: header, chunkCount: sequence, totalSamples: firstSample,
                interrupted: interrupted || failure != nil
            )
            do {
                _ = try await archive.finish(manifest)
                events?.yield(.retained(manifest))
            } catch {
                failure = (error as? WatchAudioError) ?? .interrupted
            }
        }
        return sequence == 0 ? failure ?? .invalidAudio : failure
    }

}
