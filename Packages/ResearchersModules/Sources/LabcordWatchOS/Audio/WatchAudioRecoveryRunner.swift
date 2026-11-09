import Foundation
import LabcordShared

@MainActor
enum WatchAudioRecoveryRunner {
    static func forEach(
        _ headers: [WatchAudioHeader],
        process: (WatchAudioHeader) async throws -> Void,
        onError: (Error) -> Void
    ) async throws {
        for header in headers {
            try Task.checkCancellation()
            do {
                try await process(header)
            } catch is CancellationError {
                if Task.isCancelled { throw CancellationError() }
                onError(CancellationError())
            } catch {
                onError(error)
            }
        }
    }

    static func refreshSaved(
        _ header: WatchAudioHeader,
        query: (WatchAudioMessage) async throws -> WatchAudioReceipt,
        deliver: (WatchAudioReceipt) async throws -> Void,
        stallTimeout: Duration = .seconds(30), pollInterval: Duration = .seconds(1)
    ) async throws {
        let challenge = UUID()
        let clock = ContinuousClock()
        var deadline = clock.now.advanced(by: stallTimeout)
        var lastProgress: Int64 = -1
        var receipt = try await query(.beginSavedVerification(header, challenge))
        guard receipt.savedRecordID == nil else { throw WatchAudioError.conflict }
        while true {
            try Task.checkCancellation()
            guard receipt.header == header, receipt.verificationID == challenge else {
                throw WatchAudioError.conflict
            }
            if let failure = receipt.failure { throw failure }
            if receipt.savedRecordID != nil { break }
            guard let progress = receipt.verificationProgress, progress >= 0,
                  progress >= lastProgress else { throw WatchAudioError.conflict }
            if progress > lastProgress {
                lastProgress = progress
                deadline = clock.now.advanced(by: stallTimeout)
            }
            guard clock.now < deadline else { throw WatchAudioError.incomplete }
            try await Task.sleep(for: pollInterval)
            receipt = try await query(.savedVerificationResult(header, challenge))
        }
        try await deliver(receipt)
    }
}
