import AVFoundation
import Foundation
import LabcordShared

extension WatchAudioReceiver {
    nonisolated static var incomingRoot: URL {
        URL.applicationSupportDirectory.appending(path: "WatchAudioIncoming")
    }

    nonisolated public static func retainIncomingFile(
        _ temporaryURL: URL, maximumBytes: Int = 256 * 1_024 * 1_024
    ) throws -> URL {
        let size = try temporaryURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard temporaryURL.isFileURL, size > 0, size <= 200_000 else {
            throw WatchAudioError.invalidAudio
        }
        let existing = (try? FileManager.default.contentsOfDirectory(
            at: incomingRoot, includingPropertiesForKeys: [.fileSizeKey]
        )) ?? []
        let used = existing.reduce(0) { total, url in
            total + ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        guard size <= maximumBytes, used <= maximumBytes - size else {
            throw WatchAudioError.storageFull
        }
        let destination = incomingRoot.appendingPathComponent("\(UUID().uuidString).chunk")
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        try FileManager.default.copyItem(at: temporaryURL, to: destination)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: destination.path
        )
        return destination
    }

    func retryIncomingFiles() async -> Bool {
        let incoming = (try? FileManager.default.contentsOfDirectory(
            at: Self.incomingRoot, includingPropertiesForKeys: nil
        )) ?? []
        var hasFailure = false
        for url in incoming where url.pathExtension == "chunk" {
            do { _ = try await receiveRetainedFile(url) } catch { hasFailure = true }
        }
        return hasFailure
    }

    public func receiveRetainedFile(_ url: URL) async throws -> WatchAudioReceipt {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 200_000 else { throw WatchAudioError.invalidAudio }
        let data = try Data(contentsOf: url)
        guard data.count <= 200_000 else { throw WatchAudioError.invalidAudio }
        let chunk = try JSONDecoder().decode(WatchAudioChunk.self, from: data)
        return try await WatchAudioRetainedHandoff.deliver(url: url, root: Self.incomingRoot) {
            try await receive(.chunk(chunk))
        }
    }

    func requireVerifiedSavedReceipt(_ receipt: WatchAudioReceipt) async throws {
        guard receipt.savedRecordID != nil else { return }
        guard receipt.contentDigest != nil else { throw WatchExperimentError.resultUnknown }
        do {
            try await validateSavedReceipt(receipt)
        } catch let error as WatchAudioError {
            throw error.watchExperimentError
        } catch {
            throw WatchExperimentError.storageFailed
        }
    }

    func validateSavedReceipt(
        _ receipt: WatchAudioReceipt, progress: (@Sendable (Int64) -> Void)? = nil
    ) async throws {
        guard let savedID = receipt.savedRecordID,
              let digest = receipt.contentDigest else { return }
        guard savedID == receipt.header.recordingID, let manifest = receipt.manifest,
              let detail = try client.loadResultDetail(receipt.header.experimentID),
              let record = detail.records.first(where: {
                  $0.id == savedID && $0.type == .audio
              }), let path = record.filePath else { throw WatchAudioError.conflict }
        let url = URL.applicationSupportDirectory.appending(path: path)
        let header = receipt.header
        let verification = Task.detached(priority: .utility) {
            try WatchAudioStoredPCMVerifier.verifyDigest(
                url, header: header, manifest: manifest, expected: digest, progress: progress
            )
        }
        try await withTaskCancellationHandler {
            try await verification.value
        } onCancel: {
            verification.cancel()
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw WatchAudioError.storageFailed
        }
    }

    func acceptChunk(_ chunk: WatchAudioChunk) async throws -> WatchAudioReceipt {
        guard chunk.isValid else { throw WatchAudioError.invalidAudio }
        let receipt = try await archive.statusEnsuringArchive(chunk.header)
        if receipt.isCancelled { return receipt }
        if receipt.savedRecordID == chunk.header.recordingID, receipt.contentDigest != nil {
            try await validateSavedReceipt(receipt)
            guard let manifest = receipt.manifest, chunk.sequence < manifest.chunkCount,
                  chunk.firstSample + chunk.sampleCount <= manifest.totalSamples,
                  let detail = try client.loadResultDetail(chunk.header.experimentID),
                  let record = detail.records.first(where: {
                      $0.id == chunk.header.recordingID && $0.type == .audio
                  }), let path = record.filePath else { throw WatchAudioError.conflict }
            let url = URL.applicationSupportDirectory.appending(path: path)
            try WatchAudioStoredPCMVerifier.verifyChunk(
                url, header: chunk.header, chunk: chunk
            )
            return receipt
        }
        do {
            return try await archive.accept(chunk)
        } catch WatchAudioError.conflict {
            let current = try await archive.statusIfPresent(chunk.header)
            if current.isCancelled { return current }
            throw WatchAudioError.conflict
        }
    }

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
        var receipt = try await archive.statusEnsuringArchive(header)
        if receipt.savedRecordID == nil {
            let message: WatchAudioMessage = command.operation == .confirmRecord
                ? .confirm(header) : .cancel(header)
            do {
                _ = try await receive(message)
            } catch let error as WatchAudioError {
                throw error.watchExperimentError
            }
            while let work = processing[id] {
                await work.value
                try Task.checkCancellation()
            }
            receipt = try await archive.statusEnsuringArchive(header)
        }
        guard receipt.savedRecordID == id || receipt.isCancelled else {
            throw (failures[id] ?? .incomplete).watchExperimentError
        }
        try await requireVerifiedSavedReceipt(receipt)
        return WatchExperimentResponse(
            requestID: command.requestID, phase: .completed,
            record: WatchRecordSnapshot(
                id: id, kind: .audio, phase: receipt.isCancelled ? .cancelled : .saved
            )
        )
    }

    public func receive(
        _ data: Data, verificationProgress: (@Sendable (Int64) -> Void)? = nil
    ) async throws -> Data {
        guard data.count <= 200_000 else { throw WatchAudioError.invalidAudio }
        let message = try JSONDecoder().decode(WatchAudioMessage.self, from: data)
        let receipt: WatchAudioReceipt
        if case let .verifySaved(header, challenge) = message {
            let saved = try await receiptForVerification(header)
            try await validateSavedReceipt(saved, progress: verificationProgress)
            receipt = WatchAudioReceipt(
                header: saved.header, receivedSequences: saved.receivedSequences,
                manifest: saved.manifest, savedRecordID: saved.savedRecordID,
                contentDigest: saved.contentDigest, verificationID: challenge
            )
        } else {
            receipt = try await receive(message)
        }
        return try JSONEncoder().encode(receipt)
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

    func assemble(
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
