import Foundation
import LabcordShared
import LabcordWatchOS

extension WatchRecordingService {
    func capture(_ event: WatchAudioCaptureEvent, experimentID: UUID, recordID: UUID) {
        guard !invalidatedVoiceStarts.contains(recordID),
              !transfer.isCancellationPending(recordingID: recordID) else { return }
        switch event {
        case let .recording(header):
            var record = voice(header)
            record.phase = .capturing
            record.captureCompleteConfirmed = false
            publish(record)
        case let .retaining(header, throughSample):
            var record = voice(header)
            record.phase = .capturing
            record.captureCompleteConfirmed = false
            record.originalRetained = true
            record.elapsedSeconds = Int(throughSample / Int64(header.sampleRate))
            publish(record)
        case let .retained(manifest):
            var record = voice(manifest.header)
            record.phase = .transferring
            record.originalRetained = true
            record.elapsedSeconds = Int(manifest.totalSamples / Int64(manifest.header.sampleRate))
            if manifest.interrupted {
                record.detail = "녹음이 중단됐어요. 확보한 구간을 보관하고 복구하고 있어요."
            }
            publish(record)
            Task { await transfer.recover() }
        case .failed:
            var record = records[recordID] ?? WatchRecordPresentation(
                id: recordID, experimentID: experimentID, kind: .voice
            )
            guard record.experimentID == experimentID else { return }
            record.phase = .failed
            record.canAutoSave = false
            record.detail = "녹음을 완료하지 못했어요. 확보한 구간은 유지해요."
            publish(record)
        }
    }

    func restoreLocalRecords(recordID: UUID? = nil) async throws {
        for header in try await archive.headers()
            where recordID == nil || header.recordingID == recordID {
            do {
                try await restoreLocalRecord(header)
            } catch {
                failed(header, detail: "보관된 기록을 확인하지 못했어요. 원본은 유지해요.")
            }
        }
    }

    private func restoreLocalRecord(_ header: WatchAudioHeader) async throws {
        let local = try await archive.status(header)
        let remote = try await archive.remoteReceipt(header)
        var record = await voiceWithLocalStatus(header, local: local)
        if transfer.isCancellationPending(header) {
            record.phase = .saving
            record.detail = "녹음 취소를 확인하고 있어요."
        } else if recorder.activeRecording == header {
            record.phase = .capturing
        } else if local.isCancelled {
            record.phase = .cancelled
        } else if local.savedRecordID == header.recordingID {
            _ = try await archive.completeManifest(header)
            record.phase = .saved
        } else if local.manifest != nil {
            record.phase = .transferring
        } else {
            record.phase = .failed
            if WatchRecordPresentation.isEmptyVoiceCapture(
                local: local, remote: remote, hasActiveCapture: recorder.activeRecording != nil
            ) {
                // A header is written before capture starts. No local or remote receipt
                // means there are no retained samples to recover; keep the header.
                record.captureRejectedBeforeStart = true
                record.detail = "저장된 음성 구간이 없어요. 다시 녹음해주세요."
            } else {
                record.detail = "보관된 구간을 확인해주세요. 원본은 유지해요."
            }
        }
        if let manifest = local.manifest {
            record.elapsedSeconds = Int(manifest.totalSamples / Int64(header.sampleRate))
        }
        if let remote, acceptTranscript(remote.transcript, into: &record),
           remote.hasTranscriptConflict == true {
            record.hasTranscriptConflict = true
        }
        publish(record)
        if let remote {
            // 저장 ACK는 원본 전체와 다시 대조한 뒤 화면에 반영한다.
            if remote.savedRecordID != nil { try await archive.acknowledgeSaved(remote) }
            await receiveAudio(remote)
        }
    }

    func receiveAudio(_ receipt: WatchAudioReceipt) async {
        if transfer.isCancellationPending(receipt.header), !receipt.isCancelled { return }
        await processAudio(receipt)
    }

    private func processAudio(_ receipt: WatchAudioReceipt) async {
        do {
            let local = try await archive.status(receipt.header)
            var record = await voiceWithLocalStatus(receipt.header, local: local)
            if let manifest = local.manifest {
                record.elapsedSeconds = Int(
                    manifest.totalSamples / Int64(receipt.header.sampleRate)
                )
            }
            if acceptTranscript(receipt.transcript, into: &record),
               receipt.hasTranscriptConflict == true {
                record.hasTranscriptConflict = true
            }
            record.canAutoSave = false
            if receipt.savedRecordID == receipt.header.recordingID,
               local.savedRecordID == receipt.header.recordingID {
                try await archive.acknowledgeSaved(receipt)
                record.phase = .saved
                record.detail = nil
            } else if receipt.isCancelled {
                record.phase = .cancelled
                record.detail = "취소 결과를 확인했어요. 보관 원본은 유지해요."
            } else if recorder.activeRecording == receipt.header {
                record = capturing(record)
            } else if let failure = receipt.failure {
                record.phase = .failed
                record.detail = failure == .recognitionUnavailable
                    ? "전사할 수 없어요. iPhone 권한·언어 설정과 연결을 확인해주세요."
                    : "기록 처리를 완료하지 못했어요. 보관한 원본으로 다시 시도해주세요."
            } else if recorder.activeRecording == nil, local.receivedSequences.isEmpty,
                      local.manifest == nil, receipt.receivedSequences.isEmpty,
                      receipt.manifest == nil, receipt.savedRecordID == nil,
                      !receipt.isReviewing {
                record.phase = .failed
                record.captureRejectedBeforeStart = true
                record.detail = "저장된 음성 구간이 없어요. 다시 녹음해주세요."
            } else if receipt.isReviewing {
                let manifest = try await archive.completeManifest(receipt.header)
                guard receipt.manifest == manifest,
                      receipt.receivedSequences == Array(0..<manifest.chunkCount),
                      record.isFinalTranscript else { throw WatchAudioError.incomplete }
                record.phase = .review
                record.canAutoSave = true
            } else {
                record.phase = receipt.transcript == nil ? .transferring : .transcribing
            }
            publish(record)
        } catch {
            failed(receipt.header, detail: "수신·저장 확인을 대조하지 못했어요. 원본은 유지해요.")
        }
    }

    private func capturing(_ existing: WatchRecordPresentation) -> WatchRecordPresentation {
        var record = existing
        record.phase = .capturing
        record.captureCompleteConfirmed = false
        record.detail = nil
        return record
    }

    private func hasSealedOriginal(
        _ header: WatchAudioHeader, local: WatchAudioReceipt
    ) async -> Bool {
        guard let manifest = local.manifest, !local.receivedSequences.isEmpty,
              recorder.activeRecording != header else { return false }
        if records[header.recordingID]?.captureCompleteConfirmed == true,
           local.receivedSequences.count == manifest.chunkCount { return true }
        guard (try? await archive.completeManifest(header)) != nil else { return false }
        return recorder.activeRecording != header
    }

    private func voiceWithLocalStatus(
        _ header: WatchAudioHeader, local: WatchAudioReceipt
    ) async -> WatchRecordPresentation {
        let captureComplete = await hasSealedOriginal(header, local: local)
        var record = voice(header)
        record.originalRetained = !local.receivedSequences.isEmpty
        record.captureCompleteConfirmed = captureComplete
        return record
    }

    func receiveRecord(_ snapshot: WatchRecordSnapshot, experimentID: UUID) {
        guard snapshot.experimentID == experimentID else { return }
        if let revision = snapshot.revision {
            if let previous = recordVersions[snapshot.id], revision <= previous { return }
            recordVersions[snapshot.id] = revision
        } else if recordVersions[snapshot.id] != nil {
            return
        }
        let record = WatchRecordPresentation(
            snapshot: snapshot, experimentID: experimentID, revision: snapshot.revision ?? 0
        )
        publish(record)
    }

    func failed(_ header: WatchAudioHeader, detail: String) {
        var record = voice(header)
        record.phase = .failed
        record.canAutoSave = false
        record.detail = detail
        publish(record)
    }

    private func voice(_ header: WatchAudioHeader) -> WatchRecordPresentation {
        var record = records[header.recordingID] ?? WatchRecordPresentation(
            id: header.recordingID, experimentID: header.experimentID, kind: .voice
        )
        record.captureRejectedBeforeStart = false
        record.startedAt = header.startedAt
        return record
    }

    @discardableResult
    private func acceptTranscript(
        _ transcript: WatchAudioTranscript?, into record: inout WatchRecordPresentation
    ) -> Bool {
        guard let transcript, transcript.header.experimentID == record.experimentID,
              transcript.header.recordingID == record.id else { return false }
        let id = record.id
        if retiredGenerations[id, default: []].contains(transcript.generationID) { return false }
        if let previous = transcriptVersions[id] {
            if previous.generation == transcript.generationID {
                guard transcript.revision >= previous.revision else { return false }
            } else {
                retiredGenerations[id, default: []].insert(previous.generation)
            }
        }
        transcriptVersions[id] = (transcript.generationID, transcript.revision)
        record.transcript = transcript.text
        record.isFinalTranscript = transcript.isFinal
        return true
    }
}
