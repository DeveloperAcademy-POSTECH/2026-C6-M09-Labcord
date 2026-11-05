import AVFoundation
import Foundation
import LabcordShared
import OSLog

private struct WatchAudioPipeline {
    let transcriber: WatchAudioTranscriber
    var nextSequence = 0
}

/// Core routes audio messages here and returns the encoded durable receipt to Watch.
@MainActor
public final class WatchAudioReceiver {
    public typealias Context = @MainActor (UUID) throws -> [String]

    private let logger = Logger(subsystem: "Labcord", category: "WatchAudio")

    private let archive: WatchAudioArchive
    private let client: ExperimentClient
    private let context: Context
    private let locale: Locale
    private var pipelines: [UUID: WatchAudioPipeline] = [:]
    private var processing: [UUID: Task<Void, Never>] = [:]
    private var processIDs: [UUID: UUID] = [:]
    private var observers: [UUID: AsyncStream<WatchAudioTranscript>.Continuation] = [:]
    private let reviewGate = WatchAudioReviewGate()
    private var latestTranscripts: [UUID: WatchAudioTranscript] = [:]
    private var transcriptConflicts: Set<UUID> = []
    public private(set) var failures: [UUID: WatchAudioError] = [:]
    public private(set) var hasIncomingFileFailure = false

    public init(
        archive: WatchAudioArchive, client: ExperimentClient,
        locale: Locale = .current, contextualStrings: @escaping Context
    ) {
        self.archive = archive
        self.client = client
        self.locale = locale
        context = contextualStrings
    }

    public func transcripts() -> AsyncStream<WatchAudioTranscript> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<WatchAudioTranscript>.makeStream(
            bufferingPolicy: .bufferingNewest(8)
        )
        observers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.observers.removeValue(forKey: id) }
        }
        return stream
    }

    public func receive(_ data: Data) async throws -> Data {
        guard data.count <= 200_000 else { throw WatchAudioError.invalidAudio }
        let message = try JSONDecoder().decode(WatchAudioMessage.self, from: data)
        let receipt: WatchAudioReceipt
        switch message {
        case let .chunk(chunk): receipt = try await archive.accept(chunk)
        case let .finish(manifest): receipt = try await archive.finish(manifest)
        case let .status(header): receipt = try await archive.status(header)
        case let .confirm(header):
            receipt = try await archive.status(header)
            guard reviewGate.contains(header.recordingID) else {
                throw WatchAudioError.incomplete
            }
            reviewGate.resolve(header.recordingID, save: true)
        case let .cancel(header):
            guard try client.loadResultDetail(header.experimentID)?.records.contains(where: {
                $0.id == header.recordingID
            }) != true else { throw WatchAudioError.conflict }
            receipt = try await archive.cancel(header)
            reviewGate.resolve(header.recordingID, save: false)
            pipelines.removeValue(forKey: header.recordingID)?.transcriber.cancel()
        }
        schedule(receipt.header)
        return try JSONEncoder().encode(WatchAudioReceipt(
            header: receipt.header, receivedSequences: receipt.receivedSequences,
            manifest: receipt.manifest, savedRecordID: receipt.savedRecordID,
            isCancelled: receipt.isCancelled,
            isReviewing: reviewGate.contains(receipt.header.recordingID),
            failure: failures[receipt.header.recordingID],
            transcript: latestTranscripts[receipt.header.recordingID],
            hasTranscriptConflict: transcriptConflicts.contains(receipt.header.recordingID)
                ? true : nil
        ))
    }

    /// Call once after launching; no dependence on a new capture or a previously delivered ACK.
    public func recover() async throws {
        let incoming = (try? FileManager.default.contentsOfDirectory(
            at: Self.incomingRoot, includingPropertiesForKeys: nil
        )) ?? []
        for url in incoming where url.pathExtension == "chunk" {
            do { _ = try await receiveRetainedFile(url) } catch { hasIncomingFileFailure = true }
        }
        for header in try await archive.headers() { schedule(header) }
    }

    func acceptRetainedChunk(_ chunk: WatchAudioChunk) async throws -> WatchAudioReceipt {
        let receipt = try await archive.accept(chunk)
        schedule(chunk.header)
        return receipt
    }

    /// #173 routes voice confirm/cancel here instead of the photo/video reducer.
    public func handleRecordCommand(
        _ command: WatchExperimentCommand
    ) async throws -> WatchExperimentResponse {
        guard let experimentID = command.experimentID, let id = command.targetID,
              let header = try await archive.headers().first(where: {
                $0.experimentID == experimentID && $0.recordingID == id
              }) else { throw WatchExperimentError.invalidState }
        guard command.operation == .confirmRecord || command.operation == .cancelRecord else {
            throw WatchExperimentError.invalidPayload
        }
        var receipt = try await archive.status(header)
        if receipt.savedRecordID != nil, command.operation == .cancelRecord {
            throw WatchExperimentError.invalidState
        }
        if receipt.savedRecordID == nil {
            let message: WatchAudioMessage = command.operation == .confirmRecord
                ? .confirm(header) : .cancel(header)
            _ = try await receive(JSONEncoder().encode(message))
            await processing[id]?.value
            receipt = try await archive.status(header)
        }
        guard receipt.savedRecordID == id || receipt.isCancelled else {
            throw failures[id] ?? WatchAudioError.storageFailed
        }
        return WatchExperimentResponse(
            requestID: command.requestID, phase: .completed,
            record: WatchRecordSnapshot(
                id: id, kind: .audio, phase: receipt.isCancelled ? .cancelled : .saved
            )
        )
    }

    public func stop() {
        processing.values.forEach { $0.cancel() }
        processing.removeAll()
        processIDs.removeAll()
        pipelines.values.forEach { $0.transcriber.cancel() }
        pipelines.removeAll()
        reviewGate.cancelAll()
    }

    private func schedule(_ header: WatchAudioHeader) {
        guard processing[header.recordingID] == nil else { return }
        let processID = UUID()
        processIDs[header.recordingID] = processID
        processing[header.recordingID] = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.processIDs[header.recordingID] == processID {
                    self.processing.removeValue(forKey: header.recordingID)
                    self.processIDs.removeValue(forKey: header.recordingID)
                }
            }
            do {
                try await self.process(header)
                self.failures.removeValue(forKey: header.recordingID)
            } catch is CancellationError {
                return
            } catch {
                guard self.processIDs[header.recordingID] == processID else { return }
                self.pipelines.removeValue(forKey: header.recordingID)?.transcriber.cancel()
                let underlying = error as NSError
                let domain = underlying.domain
                let code = underlying.code
                self.logger.error("Watch audio error: \(domain, privacy: .public) code=\(code)")
                self.failures[header.recordingID] = (error as? WatchAudioError)
                    ?? .recognitionUnavailable
            }
        }
    }

    private func process(_ header: WatchAudioHeader) async throws {
        let receipt = try await archive.status(header)
        guard receipt.savedRecordID == nil, !receipt.isCancelled else { return }
        // Existing records, including user-edited transcripts, are never overwritten.
        if try await acknowledgeExistingRecord(header) { return }
        guard !receipt.receivedSequences.isEmpty else { return }
        try ensureWatchAudioPipeline(header)
        guard var pipeline = pipelines[header.recordingID] else {
            throw WatchAudioError.conflict
        }
        let sequences = Set(receipt.receivedSequences)
        while sequences.contains(pipeline.nextSequence) {
            try Task.checkCancellation()
            try pipeline.transcriber.append(await archive.chunk(header, pipeline.nextSequence))
            pipeline.nextSequence += 1
        }
        pipelines[header.recordingID] = pipeline
        guard let manifest = receipt.manifest,
              pipeline.nextSequence == manifest.chunkCount else { return }
        try await finish(header, pipeline: pipeline, manifest: manifest)
    }

    private func finish(
        _ header: WatchAudioHeader, pipeline: WatchAudioPipeline, manifest: WatchAudioManifest
    ) async throws {
        _ = try await archive.completeManifest(header)
        let transcript = try await pipeline.transcriber.finish()
        try Task.checkCancellation()
        guard try !(await archive.status(header)).isCancelled else { return }
        failures.removeValue(forKey: header.recordingID)
        guard await reviewGate.wait(header.recordingID) else { return }
        try Task.checkCancellation()
        guard try !(await archive.status(header)).isCancelled else { return }
        let source = try await assemble(header, manifest: manifest)
        guard try !(await archive.status(header)).isCancelled else { return }
        // 전사·검토 대기 중 iPhone에서 생긴 저장본도 덮어쓰지 않습니다.
        if try await acknowledgeExistingRecord(header, comparing: transcript) {
            pipelines.removeValue(forKey: header.recordingID)
            return
        }
        // Repository moves this staging copy; the archive's original chunks remain intact.
        do {
            try client.saveAudio(
                header.experimentID, header.recordingID, header.startedAt, source, transcript
            )
        } catch { throw WatchAudioError.storageFailed }
        _ = try await archive.markSaved(header, recordID: header.recordingID)
        pipelines.removeValue(forKey: header.recordingID)
    }

    private func ensureWatchAudioPipeline(_ header: WatchAudioHeader) throws {
        if pipelines[header.recordingID] == nil {
            guard pipelines.count < 4 else { throw WatchAudioError.bufferOverflow }
            let transcriber = try WatchAudioTranscriber(
                header: header, locale: locale, contextualStrings: context(header.experimentID)
            ) { [weak self] event in
                self?.latestTranscripts[event.header.recordingID] = event
                self?.observers.values.forEach { $0.yield(event) }
            }
            pipelines[header.recordingID] = WatchAudioPipeline(transcriber: transcriber)
        }
    }

    private func assemble(
        _ header: WatchAudioHeader, manifest: WatchAudioManifest
    ) async throws -> URL {
        let url = URL.applicationSupportDirectory.appending(
            path: "WatchAudioStaging/\(header.recordingID.uuidString).caf"
        )
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16, sampleRate: Double(header.sampleRate),
            channels: 1, interleaved: false
        ) else { throw WatchAudioError.invalidAudio }
        let file = try AVAudioFile(
            forWriting: url, settings: format.settings,
            commonFormat: .pcmFormatInt16, interleaved: false
        )
        for sequence in 0..<manifest.chunkCount {
            try Task.checkCancellation()
            let chunk = try await archive.chunk(header, sequence)
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: format, frameCapacity: AVAudioFrameCount(chunk.sampleCount)
            ), let samples = buffer.int16ChannelData?[0] else {
                throw WatchAudioError.invalidAudio
            }
            buffer.frameLength = AVAudioFrameCount(chunk.sampleCount)
            chunk.pcm.copyBytes(to: UnsafeMutableRawBufferPointer(
                start: samples, count: chunk.pcm.count
            ))
            try file.write(from: buffer)
        }
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path
        )
        return url
    }
}

private extension WatchAudioReceiver {
    func acknowledgeExistingRecord(
        _ header: WatchAudioHeader, comparing transcript: String? = nil
    ) async throws -> Bool {
        if let record = try client.loadResultDetail(header.experimentID)?.records.first(where: {
            $0.id == header.recordingID
        }) {
            guard record.type == .audio, let path = record.filePath,
                  FileManager.default.fileExists(
                    atPath: URL.applicationSupportDirectory.appending(path: path).path
                  ), let storedTranscript = record.transcript else {
                throw WatchAudioError.conflict
            }
            let actualTranscript = transcript ?? latestTranscripts[header.recordingID].flatMap {
                $0.isFinal ? $0.text : nil
            }
            if let actualTranscript, storedTranscript != actualTranscript {
                transcriptConflicts.insert(header.recordingID)
            }
            _ = try await archive.markSaved(header, recordID: record.id)
            return true
        }
        return false
    }
}
