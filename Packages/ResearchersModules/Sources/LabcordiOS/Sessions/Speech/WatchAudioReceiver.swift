import AVFoundation
import Foundation
import LabcordShared
import OSLog

private struct WatchAudioPipeline {
    let transcriber: WatchAudioTranscriber
    var nextSequence = 0
}

@MainActor
public final class WatchAudioReceiver {
    public typealias Context = @MainActor (UUID) throws -> [String]

    private let logger = Logger(subsystem: "Labcord", category: "WatchAudio")

    let archive: WatchAudioArchive
    let client: ExperimentClient
    private let context: Context
    private let sessionDetail: (@MainActor (UUID) throws -> ExperimentSessionDetail)?
    private let locale: Locale
    private var pipelines: [UUID: WatchAudioPipeline] = [:]
    var processing: [UUID: Task<Void, Never>] = [:]
    private var processIDs: [UUID: UUID] = [:]
    private var pendingRerun: Set<UUID> = []
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
        sessionDetail = nil
    }

    public init(
        archive: WatchAudioArchive, client: ExperimentClient,
        locale: Locale = .current,
        sessionDetail: @escaping @MainActor (UUID) throws -> ExperimentSessionDetail
    ) {
        self.archive = archive
        self.client = client
        self.locale = locale
        self.context = { _ in [] }
        self.sessionDetail = sessionDetail
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

    public func receive(
        _ data: Data, verificationProgress: (@Sendable (Int64) -> Void)? = nil
    ) async throws -> Data {
        guard data.count <= 200_000 else { throw WatchAudioError.invalidAudio }
        let message = try JSONDecoder().decode(WatchAudioMessage.self, from: data)
        let receipt: WatchAudioReceipt
        var verificationID: UUID?
        switch message {
        case let .chunk(chunk): receipt = try await acceptChunk(chunk)
        case let .finish(manifest): receipt = try await archive.finish(manifest)
        case let .status(header): receipt = try await archive.statusEnsuringArchive(header)
        case let .verifySaved(header, challenge):
            receipt = try await receiptForVerification(header)
            verificationID = challenge
        case .beginSavedVerification, .savedVerificationResult:
            throw WatchAudioError.invalidAudio
        case let .confirm(header):
            receipt = try await archive.statusEnsuringArchive(header)
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
            releaseTranscript(header.recordingID)
        }
        try await validateSavedReceipt(receipt, progress: verificationProgress)
        schedule(receipt.header)
        return try JSONEncoder().encode(WatchAudioReceipt(
            header: receipt.header, receivedSequences: receipt.receivedSequences,
            manifest: receipt.manifest, savedRecordID: receipt.savedRecordID,
            contentDigest: receipt.contentDigest, verificationID: verificationID,
            isCancelled: receipt.isCancelled,
            isReviewing: reviewGate.contains(receipt.header.recordingID),
            failure: failures[receipt.header.recordingID],
            transcript: latestTranscripts[receipt.header.recordingID],
            hasTranscriptConflict: transcriptConflicts.contains(receipt.header.recordingID)
                ? true : nil
        ))
    }

    private func receiptForVerification(
        _ header: WatchAudioHeader
    ) async throws -> WatchAudioReceipt {
        let receipt = try await archive.statusEnsuringArchive(header)
        guard receipt.savedRecordID == header.recordingID, receipt.contentDigest != nil else {
            throw WatchAudioError.incomplete
        }
        return receipt
    }

    public func recover() async throws {
        await retryRetainedFiles()
        for header in try await archive.headers() { schedule(header) }
    }

    public func retryRetainedFiles() async {
        let incoming = (try? FileManager.default.contentsOfDirectory(
            at: Self.incomingRoot, includingPropertiesForKeys: nil
        )) ?? []
        hasIncomingFileFailure = false
        for url in incoming where url.pathExtension == "chunk" {
            do { _ = try await receiveRetainedFile(url) } catch { hasIncomingFileFailure = true }
        }
    }

    func acceptRetainedChunk(_ chunk: WatchAudioChunk) async throws -> WatchAudioReceipt {
        let receipt = try await acceptChunk(chunk)
        schedule(chunk.header)
        return receipt
    }

    public func stop() {
        processing.values.forEach { $0.cancel() }
        processing.removeAll()
        processIDs.removeAll()
        pendingRerun.removeAll()
        pipelines.values.forEach { $0.transcriber.cancel() }
        pipelines.removeAll()
        reviewGate.cancelAll()
    }

    private func ensureWatchAudioPipeline(_ header: WatchAudioHeader) async throws {
        if pipelines[header.recordingID] == nil {
            guard pipelines.count < 4 else { throw WatchAudioError.bufferOverflow }
            let detail = try sessionDetail?(header.experimentID)
            let vocabulary: SpeechSessionVocabulary?
            if let detail {
                vocabulary = await SpeechSessionVocabulary.prepare(for: detail.speechTerms)
            } else {
                vocabulary = nil
            }
            let modelHint: SpeechLanguageModelHint?
            if let detail {
                modelHint = await SpeechCustomLanguageModel.hint(
                    for: detail.speechTerms, locale: locale
                )
            } else {
                modelHint = nil
            }
            try Task.checkCancellation()
            let hints = try vocabulary?.contextualStrings ?? context(header.experimentID)
            let transcriber = try await WatchAudioTranscriber(
                header: header, locale: locale, contextualStrings: hints,
                replacements: vocabulary?.replacements ?? [:],
                units: detail?.speechUnits ?? [], languageModelHint: modelHint
            ) { [weak self] event in
                self?.latestTranscripts[event.header.recordingID] = event
                self?.observers.values.forEach { $0.yield(event) }
            }
            do {
                try Task.checkCancellation()
                let receipt = try await archive.statusEnsuringArchive(header)
                guard !receipt.isCancelled, receipt.savedRecordID == nil else {
                    throw CancellationError()
                }
                guard pipelines.count < 4 else { throw WatchAudioError.bufferOverflow }
                try Task.checkCancellation()
                pipelines[header.recordingID] = WatchAudioPipeline(transcriber: transcriber)
            } catch {
                transcriber.cancel()
                throw error
            }
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
    func schedule(_ header: WatchAudioHeader) {
        let recordingID = header.recordingID
        if processing[recordingID] != nil {
            pendingRerun.insert(recordingID)
            return
        }
        let processID = UUID()
        processIDs[recordingID] = processID
        processing[recordingID] = Task { [weak self] in
            guard let self else { return }
            defer {
                let current = self.processIDs[recordingID] == processID
                if current {
                    self.processing.removeValue(forKey: recordingID)
                    self.processIDs.removeValue(forKey: recordingID)
                }
                if current, self.pendingRerun.remove(recordingID) != nil {
                    self.schedule(header)
                }
            }
            do {
                try await self.process(header)
                self.failures.removeValue(forKey: header.recordingID)
            } catch is CancellationError {
                return
            } catch {
                guard self.processIDs[recordingID] == processID else { return }
                self.pipelines.removeValue(forKey: recordingID)?.transcriber.cancel()
                let underlying = error as NSError
                let domain = underlying.domain
                let code = underlying.code
                self.logger.error("Watch audio error: \(domain, privacy: .public) code=\(code)")
                self.failures[recordingID] = (error as? WatchAudioError)
                    ?? .recognitionUnavailable
            }
        }
    }

    func process(_ header: WatchAudioHeader) async throws {
        let receipt = try await archive.statusEnsuringArchive(header)
        if receipt.savedRecordID != nil {

            if receipt.contentDigest == nil {
                guard try await acknowledgeExistingRecord(header) else {
                    throw WatchAudioError.storageFailed
                }
            } else {

                try await validateSavedReceipt(receipt)
                try await archive.acknowledgeSavedAndCleanUp(receipt)
            }
            releaseTranscript(header.recordingID)
            return
        }
        guard !receipt.isCancelled else {
            releaseTranscript(header.recordingID)
            return
        }

        if try await acknowledgeExistingRecord(header) { return }
        guard !receipt.receivedSequences.isEmpty else { return }
        try await ensureWatchAudioPipeline(header)
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

    func finish(
        _ header: WatchAudioHeader, pipeline: WatchAudioPipeline, manifest: WatchAudioManifest
    ) async throws {
        _ = try await archive.completeManifest(header)
        let transcript = try await pipeline.transcriber.finish()
        try Task.checkCancellation()
        guard try !(await archive.statusEnsuringArchive(header)).isCancelled else { return }
        failures.removeValue(forKey: header.recordingID)
        guard await reviewGate.wait(header.recordingID) else { return }
        try Task.checkCancellation()
        guard try !(await archive.statusEnsuringArchive(header)).isCancelled else { return }
        let source = try await assemble(header, manifest: manifest)
        guard try !(await archive.statusEnsuringArchive(header)).isCancelled else { return }

        if try await acknowledgeExistingRecord(header, comparing: transcript) {
            pipelines.removeValue(forKey: header.recordingID)
            return
        }
        do {
            try client.saveAudio(
                header.experimentID, header.recordingID, header.startedAt, source, transcript
            )
        } catch { throw WatchAudioError.storageFailed }
        guard try await acknowledgeExistingRecord(header, comparing: transcript) else {
            throw WatchAudioError.storageFailed
        }
        pipelines.removeValue(forKey: header.recordingID)
        releaseTranscript(header.recordingID)
    }

    func releaseTranscript(_ id: UUID) {
        latestTranscripts.removeValue(forKey: id)
        transcriptConflicts.remove(id)
    }

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
            let savedURL = URL.applicationSupportDirectory.appending(path: path)
            try await WatchAudioStoredPCMVerifier.verify(
                savedURL, header: header, archive: archive
            )
            let actualTranscript = transcript ?? latestTranscripts[header.recordingID].flatMap {
                $0.isFinal ? $0.text : nil
            }
            if let actualTranscript, storedTranscript != actualTranscript {
                transcriptConflicts.insert(header.recordingID)
            }
            let saved = try await archive.markSaved(header, recordID: record.id)

            try? await archive.acknowledgeSavedAndCleanUp(saved)
            return true
        }
        return false
    }
}
