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

@MainActor
public final class WatchAudioRecorder {
    public let archive: WatchAudioArchive
    public var activeRecording: WatchAudioHeader? { header }
    public var isStarting: Bool { startGate.isStarting }
    public private(set) var damagedRecordingIDs: [UUID] = []
    private let engine = AVAudioEngine()
    private var header: WatchAudioHeader?
    private var continuation: AsyncThrowingStream<Data, Error>.Continuation?
    private var writer: Task<Void, Never>?
    private var interruptions: Task<Void, Never>?
    private var events: AsyncStream<WatchAudioCaptureEvent>.Continuation?
    private var interrupted = false
    private let startGate = WatchAudioStartGate()
    private var hasTap = false

    public init(archive: WatchAudioArchive) {
        self.archive = archive
    }

    public func start(
        experimentID: UUID, recordingID: UUID = UUID(), expiresAt: Date? = nil
    ) async throws -> AsyncStream<WatchAudioCaptureEvent> {
        guard header == nil, writer == nil, !startGate.isStarting, !startGate.isStopping else {
            throw WatchAudioError.conflict
        }
        guard expiresAt.map({ Date.now < $0 }) ?? true else { throw WatchAudioError.interrupted }
        try Task.checkCancellation()
        let generation = try startGate.begin()
        defer { finishStarting() }
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
            return try await begin(
                experimentID: experimentID, recordingID: recordingID, expiresAt: expiresAt,
                generation: generation
            )
        } catch {
            try? session.setActive(false)
            throw error
        }
    }

    private func begin(
        experimentID: UUID, recordingID: UUID, expiresAt: Date?, generation: UUID
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
            try checkStart(generation, header: header, expiresAt: expiresAt)
            try await requireForeground(header)
            try checkStart(generation, header: header, expiresAt: expiresAt)
        } catch {
            if self.header == header { self.header = nil }

            await markEmptyCaptureIfProven(header)
            throw error
        }
        interrupted = false
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
        interruptions = monitorInterruptions(header)
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

    private func installTap(
        input: AVAudioInputNode, format: AVAudioFormat,
        continuation: AsyncThrowingStream<Data, Error>.Continuation
    ) {
        hasTap = true
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { @Sendable buffer, _ in

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
        if writer == nil, await cancelPendingStart() { return }
        if startGate.isStopping {
            await writer?.value
            return
        }
        guard header != nil, startGate.beginStopping() else { return }
        defer { startGate.finishStopping() }
        engine.stop()
        removeTap()
        continuation?.finish()
        continuation = nil
        interruptions?.cancel()
        interruptions = nil
        await writer?.value
        writer = nil
        header = nil
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    public func stopForExperiment(_ experimentID: UUID) async throws -> [WatchAudioReceipt] {
        let stopped = header
        if let header {
            guard header.experimentID == experimentID else { throw WatchAudioError.conflict }
            await stop()
        }
        if let stopped {
            let receipt = try await archive.statusEnsuringArchive(stopped)
            if !receipt.isCancelled { _ = try await archive.completeManifest(stopped) }
        }
        var receipts: [WatchAudioReceipt] = []
        let scan = try await archive.scanHeaders()
        damagedRecordingIDs = scan.damagedRecordingIDs

        guard damagedRecordingIDs.isEmpty else { throw WatchAudioError.invalidAudio }
        for header in scan.headers where header.experimentID == experimentID {
            let receipt = try await archive.statusEnsuringArchive(header)
            if !receipt.receivedSequences.isEmpty {
                _ = try await archive.completeManifest(header)
                receipts.append(receipt)
            }
        }
        return receipts
    }

    public func recoverInterruptedRecordings() async throws {
        guard header == nil, !startGate.isStarting else { throw WatchAudioError.conflict }
        let scan = try await archive.scanHeaders()
        damagedRecordingIDs = scan.damagedRecordingIDs
        for header in scan.headers {
            try Task.checkCancellation()
            do {
                let receipt = try await archive.statusEnsuringArchive(header)
                if receipt.manifest == nil, !receipt.receivedSequences.isEmpty {
                    _ = try await archive.sealInterrupted(header)
                }
            } catch {

                damagedRecordingIDs.append(header.recordingID)
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
        var archiveFailed = false
        var pending = Data()
        do {
            for try await pcm in stream {
                pending.append(pcm)
                while pending.count >= 16_384 {
                    let chunk = WatchAudioChunk(
                        header: header, sequence: sequence, firstSample: firstSample,
                        pcm: Data(pending.prefix(16_384))
                    )
                    do { _ = try await archive.accept(chunk) } catch {
                        archiveFailed = true
                        throw error
                    }
                    pending.removeFirst(16_384)
                    firstSample += chunk.sampleCount
                    sequence += 1
                    events?.yield(.retaining(header, throughSample: firstSample))
                }
            }
        } catch {
            failure = (error as? WatchAudioError) ?? .interrupted
            engine.stop()
            removeTap()
        }
        if !archiveFailed, !pending.isEmpty {
            let chunk = WatchAudioChunk(
                header: header, sequence: sequence, firstSample: firstSample, pcm: pending
            )
            do {
                _ = try await archive.accept(chunk)
                firstSample += chunk.sampleCount
                sequence += 1
            } catch { failure = (error as? WatchAudioError) ?? .interrupted }
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
        if sequence == 0, failure == nil, !interrupted {
            await markEmptyCaptureIfProven(header)
        }
        return sequence == 0 ? failure ?? .invalidAudio : failure
    }

}

extension WatchAudioRecorder {

    @discardableResult
    public func cancelPendingStart() async -> Bool {
        await startGate.cancelPending()
    }

}

private extension WatchAudioRecorder {
    func markEmptyCaptureIfProven(_ header: WatchAudioHeader) async {
        _ = try? await archive.cancelEmptyBeforeCapture(header)
    }

    func requireForeground(_ header: WatchAudioHeader) async throws {
        guard WKApplication.shared().applicationState == .active else {
            self.header = nil
            _ = try await archive.cancel(header)
            throw WatchAudioError.interrupted
        }
    }

    private func checkStart(
        _ generation: UUID, header: WatchAudioHeader, expiresAt: Date?
    ) throws {
        try Task.checkCancellation()
        guard startGate.accepts(generation), self.header == header else {
            throw CancellationError()
        }
        guard expiresAt.map({ Date.now < $0 }) ?? true else { throw WatchAudioError.interrupted }
    }

    private func finishStarting() {
        startGate.finish()
    }

    func monitorInterruptions(_ header: WatchAudioHeader) -> Task<Void, Never> {
        Task { [weak self] in
            for await notification in NotificationCenter.default.notifications(
                named: AVAudioSession.interruptionNotification
            ) {
                guard let self, self.header == header else { return }
                guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey]
                        as? UInt,
                      AVAudioSession.InterruptionType(rawValue: rawType) == .began else {
                    continue
                }
                self.interrupted = true
                await self.stop()
                return
            }
        }
    }
}
