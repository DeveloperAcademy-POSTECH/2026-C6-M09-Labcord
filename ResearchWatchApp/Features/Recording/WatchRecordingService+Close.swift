import Foundation
import LabcordShared
import LabcordWatchOS

extension WatchRecordingService {
    func finishVoiceForExperiment(_ experimentID: UUID) async throws {
        guard closingExperiments.isEmpty else { throw WatchAudioError.conflict }
        closingExperiments.insert(experimentID)
        defer { closingExperiments.remove(experimentID) }
        try await waitForPendingVoiceStarts()
        if let active = recorder.activeRecording {
            guard active.experimentID == experimentID else { throw WatchAudioError.conflict }
            await recorder.stop()
            try Task.checkCancellation()
        }
        try await restoreLocalRecords()
        try Task.checkCancellation()
        let scan = try await archive.scanHeaders()
        guard scan.damagedRecordingIDs.isEmpty else { throw WatchAudioError.invalidAudio }
        for header in scan.headers where header.experimentID == experimentID {
            try Task.checkCancellation()
            let receipt = try await archive.statusEnsuringArchive(header)
            if receipt.isCancelled { continue }
            let manifest = try await archive.completeManifest(header)
            guard manifest.chunkCount > 0, manifest.totalSamples > 0 else {
                throw WatchAudioError.incomplete
            }
            let hasChunks = receipt.savedRecordID == header.recordingID
                ? try await archive.needsSavedCleanup(header) : true
            guard WatchVoiceCloseGate.needsVerification(receipt, hasRetainedChunks: hasChunks)
            else { continue }
            try await WatchVoiceCloseGate.waitForSaved(
                header, manifest: manifest,
                operations: .init(
                    scheduleRecovery: { Task { await self.transfer.recover() } },
                    status: { try await self.archive.remoteReceipt(header) },
                    confirm: { try await self.transfer.confirm(header) },
                    verify: { try await self.transfer.verifySaved(header) }
                )
            )
        }
    }

    private func waitForPendingVoiceStarts() async throws {
        for recordID in pendingVoiceStarts {
            while pendingVoiceStarts.contains(recordID), voiceStartTasks[recordID] == nil {
                try await Task.sleep(for: .milliseconds(20))
            }
            if let task = voiceStartTasks[recordID] {
                try await task.value
            } else if recorder.activeRecording?.recordingID != recordID {
                throw WatchAudioError.interrupted
            }
            try Task.checkCancellation()
        }
    }
}
