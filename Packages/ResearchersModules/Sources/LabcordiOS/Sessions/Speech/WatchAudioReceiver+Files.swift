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

    public func receiveRetainedFile(_ url: URL) async throws -> WatchAudioReceipt {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 200_000 else { throw WatchAudioError.invalidAudio }
        let data = try Data(contentsOf: url)
        guard data.count <= 200_000 else { throw WatchAudioError.invalidAudio }
        let chunk = try JSONDecoder().decode(WatchAudioChunk.self, from: data)
        return try await WatchAudioRetainedHandoff.deliver(url: url, root: Self.incomingRoot) {
            try await acceptRetainedChunk(chunk)
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
        return try await archive.accept(chunk)
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
        if receipt.savedRecordID != nil, command.operation == .cancelRecord {
            throw WatchExperimentError.invalidState
        }
        if receipt.savedRecordID == nil {
            let message: WatchAudioMessage = command.operation == .confirmRecord
                ? .confirm(header) : .cancel(header)
            do {
                _ = try await receive(JSONEncoder().encode(message))
            } catch let error as WatchAudioError {
                throw error.watchExperimentError
            }
            await processing[id]?.value
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

}
