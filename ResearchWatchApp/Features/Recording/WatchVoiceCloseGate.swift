import Foundation
import LabcordShared

@MainActor
enum WatchVoiceCloseGate {
    static func needsVerification(_ receipt: WatchAudioReceipt, hasRetainedChunks: Bool) -> Bool {
        receipt.savedRecordID != receipt.header.recordingID || hasRetainedChunks
    }

    struct Operations {
        var scheduleRecovery: () async -> Void
        var status: () async throws -> WatchAudioReceipt?
        var confirm: () async throws -> WatchAudioReceipt
        var verify: () async throws -> WatchAudioReceipt
    }

    static func waitForSaved(
        _ header: WatchAudioHeader,
        manifest: WatchAudioManifest,
        timeout: Duration = .seconds(30),
        pollInterval: Duration = .seconds(1),
        operations: Operations
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        var confirmed = false
        while clock.now < deadline {
            try Task.checkCancellation()
            await operations.scheduleRecovery()
            try checkDeadline(deadline)
            if let receipt = try await operations.status() {
                try checkDeadline(deadline)
                try validate(receipt, header: header)
                if let savedID = receipt.savedRecordID {
                    guard savedID == header.recordingID else { throw WatchAudioError.conflict }
                    let verified = try await operations.verify()
                    try Task.checkCancellation()
                    guard verified.header == header, verified.savedRecordID == header.recordingID,
                          verified.manifest == manifest,
                          verified.contentDigest != nil, verified.verificationID != nil else {
                        throw WatchAudioError.conflict
                    }
                    return
                }
                if receipt.isReviewing, !confirmed {
                    guard receipt.hasTranscriptConflict != true else {
                        throw WatchAudioError.conflict
                    }
                    if let transcript = receipt.transcript, transcript.header == header,
                       transcript.isFinal, transcript.throughSample == manifest.totalSamples,
                       receipt.manifest == manifest,
                       receipt.receivedSequences == Array(0..<manifest.chunkCount) {
                        let result = try await operations.confirm()
                        try checkDeadline(deadline)
                        guard result.header == header, !result.isCancelled else {
                            throw WatchAudioError.conflict
                        }
                        if let failure = result.failure { throw failure }
                        confirmed = true
                    }
                }
            }
            try await Task.sleep(for: pollInterval)
        }
        throw WatchAudioError.incomplete
    }
    private static func checkDeadline(_ deadline: ContinuousClock.Instant) throws {
        try Task.checkCancellation()
        guard ContinuousClock().now < deadline else { throw WatchAudioError.incomplete }
    }

    private static func validate(_ receipt: WatchAudioReceipt, header: WatchAudioHeader) throws {
        guard receipt.header == header, !receipt.isCancelled else {
            throw WatchAudioError.conflict
        }
        if let failure = receipt.failure { throw failure }
    }

}
