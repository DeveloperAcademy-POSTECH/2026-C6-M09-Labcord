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
    private var cancelling: Set<UUID> = []
    private var verifiedSaved: Set<UUID> = []
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

    func receive(_ message: WatchAudioMessage) async throws -> WatchAudioReceipt {
        let receipt: WatchAudioReceipt
        switch message {
        case let .chunk(chunk): receipt = try await acceptChunk(chunk)
        case let .finish(manifest): receipt = try await archive.finish(manifest)
        case let .status(header): receipt = try await archive.statusIfPresent(header)
        case let .confirm(header):
            try await archive.confirm(header)
            receipt = try await archive.statusIfPresent(header)
        case let .cancel(header):
            receipt = try await cancel(header)
        case .verifySaved, .beginSavedVerification, .savedVerificationResult:
            throw WatchAudioError.invalidAudio
        }
        scheduleIfNeeded(receipt)
        return try await checkedReceipt(receipt)
    }

    func currentReceipt(_ header: WatchAudioHeader) async throws -> WatchAudioReceipt {
        try await checkedReceipt(archive.statusIfPresent(header))
    }

    private func checkedReceipt(_ receipt: WatchAudioReceipt) async throws -> WatchAudioReceipt {
        let id = receipt.header.recordingID
        if receipt.isSavedAcknowledgement, !verifiedSaved.contains(id) {
            try await validateSavedReceipt(receipt)
            verifiedSaved.insert(id)
        }
        if receipt.savedRecordID != nil, receipt.contentDigest == nil, processing[id] == nil {
            schedule(receipt.header)
        }
        return makeReceipt(receipt)
    }

    private func makeReceipt(_ receipt: WatchAudioReceipt) -> WatchAudioReceipt {
        let id = receipt.header.recordingID
        let terminal = receipt.isCancelled || receipt.isSavedAcknowledgement
        let transcript = latestTranscripts[id]
        return WatchAudioReceipt(
            header: receipt.header, receivedSequences: receipt.receivedSequences,
            manifest: receipt.manifest,
            savedRecordID: receipt.isSavedAcknowledgement ? receipt.savedRecordID : nil,
            contentDigest: receipt.contentDigest, isCancelled: receipt.isCancelled,
            isReviewing: !terminal && transcript?.isFinal == true && failures[id] == nil,
            failure: terminal ? nil : failures[id],
            transcript: transcript, hasTranscriptConflict: transcriptConflicts.contains(id)
                && transcript?.isFinal == true ? true : nil
        )
    }

    private func cancel(_ header: WatchAudioHeader) async throws -> WatchAudioReceipt {
        let id = header.recordingID
        if try client.loadResultDetail(header.experimentID)?.records.contains(where: {
            $0.id == id
        }) == true {
            let receipt = try await archive.statusIfPresent(header)
            if receipt.isSavedAcknowledgement { return receipt }
            if processing[id] == nil { schedule(header) }
            return receipt
        }
        guard cancelling.insert(id).inserted else {
            return try await archive.statusIfPresent(header)
        }
        defer { cancelling.remove(id) }
        let receipt = try await archive.cancel(header)
        processing.removeValue(forKey: id)?.cancel()
        processIDs.removeValue(forKey: id)
        pendingRerun.remove(id)
        pipelines.removeValue(forKey: id)?.transcriber.cancel()
        releaseTranscript(id)
        failures.removeValue(forKey: id)
        return receipt
    }

    public func recover() async throws {
        await retryRetainedFiles()
        for header in try await archive.headers() {
            do {
                let receipt = try await archive.statusIfPresent(header)
                if receipt.savedRecordID == nil {
                    scheduleIfNeeded(receipt)
                } else {
                    let needsCleanup = try await archive.needsSavedCleanup(header)
                    if receipt.contentDigest == nil || needsCleanup { schedule(header) }
                }
            } catch {
                failures[header.recordingID] = (error as? WatchAudioError) ?? .storageFailed
            }
        }
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
        scheduleIfNeeded(receipt)
        return try await checkedReceipt(receipt)
    }

    public func stop() {
        processing.values.forEach { $0.cancel() }
        processing.removeAll()
        processIDs.removeAll()
        pendingRerun.removeAll()
        pipelines.values.forEach { $0.transcriber.cancel() }
        pipelines.removeAll()
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
}
private extension WatchAudioReceiver {
    func scheduleIfNeeded(_ receipt: WatchAudioReceipt) {
        guard !receipt.isCancelled, receipt.savedRecordID == nil,
              !receipt.receivedSequences.isEmpty,
              !cancelling.contains(receipt.header.recordingID) else { return }
        schedule(receipt.header)
    }

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
                if self.processIDs[recordingID] == processID {
                    self.failures.removeValue(forKey: recordingID)
                }
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
        let receipt = try await archive.statusIfPresent(header)
        try Task.checkCancellation()
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
        if let transcript = latestTranscripts[header.recordingID], transcript.isFinal,
           let manifest = receipt.manifest {
            try await saveIfConfirmed(header, transcript: transcript.text, manifest: manifest)
            return
        }
        try await ensureWatchAudioPipeline(header)
        guard var pipeline = pipelines[header.recordingID] else {
            throw WatchAudioError.conflict
        }
        let sequences = Set(receipt.receivedSequences)
        while sequences.contains(pipeline.nextSequence) {
            try Task.checkCancellation()
            let chunk = try await archive.chunk(header, pipeline.nextSequence)
            try Task.checkCancellation()
            try pipeline.transcriber.append(chunk)
            pipeline.nextSequence += 1
        }
        pipelines[header.recordingID] = pipeline
        guard let manifest = receipt.manifest,
              pipeline.nextSequence == manifest.chunkCount else { return }
        _ = try await archive.completeManifest(header)
        let transcript = try await pipeline.transcriber.finish()
        try Task.checkCancellation()
        pipelines.removeValue(forKey: header.recordingID)
        try await saveIfConfirmed(header, transcript: transcript, manifest: manifest)
    }

    func saveIfConfirmed(
        _ header: WatchAudioHeader, transcript: String, manifest: WatchAudioManifest
    ) async throws {
        guard await archive.isConfirmed(header) else { return }
        try Task.checkCancellation()
        let source = try await assemble(header, manifest: manifest)
        defer { try? FileManager.default.removeItem(at: source) }
        let receipt = try await archive.statusIfPresent(header)
        try Task.checkCancellation()
        // No actor hop between checking cancellation and committing the stable record ID.
        guard !receipt.isCancelled, !cancelling.contains(header.recordingID) else { return }
        do {
            try client.saveAudio(
                header.experimentID, header.recordingID, header.startedAt, source, transcript
            )
        } catch { throw WatchAudioError.storageFailed }
        guard try await acknowledgeExistingRecord(header, comparing: transcript) else {
            throw WatchAudioError.storageFailed
        }
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
            verifiedSaved.insert(record.id)

            try? await archive.acknowledgeSavedAndCleanUp(saved)
            return true
        }
        return false
    }
}

extension WatchAudioReceiver {
    func clearDebugData() {
        stop()
        latestTranscripts.removeAll()
        transcriptConflicts.removeAll()
        verifiedSaved.removeAll()
        failures.removeAll()
        hasIncomingFileFailure = false
    }
}
