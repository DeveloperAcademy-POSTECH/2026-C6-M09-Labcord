import Foundation
import LabcordShared
import LabcordWatchOS
import OSLog

extension WatchRecordingService {
    func logFailure(_ error: Error, stage: String, recordID: UUID? = nil) {
        let error = error as NSError
        let recordID = recordID?.uuidString ?? "none"
        logger.error("Recording failure: stage=\(stage, privacy: .public)")
        logger.error("Record=\(recordID, privacy: .public)")
        logger.error("Domain=\(error.domain, privacy: .public) code=\(error.code)")
    }

    func reconcileRecords() async throws {
        do {
            try await restoreLocalRecords()
        } catch {
            logFailure(error, stage: "reconcile")
            throw error
        }
        await transfer.recover()
        refreshVoiceLiveStatus()
    }

    func markCancelledStart(_ input: WatchRecordingUIBridge.Input) {
        if case let .cancelActiveVoiceForPause(_, recordID?) = input {
            invalidatedVoiceStarts.insert(recordID)
        }
    }

    func capture(_ event: WatchAudioCaptureEvent, experimentID: UUID, recordID: UUID) {
        retentionCache.removeValue(forKey: recordID)
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
            record.detail = "녹음을 완료하지 못했어요. 보관 상태를 확인해주세요."
            publish(record)
        }
    }

    func restoreLocalRecords(recordID: UUID? = nil) async throws {
        for header in try await archive.headers()
            where recordID == nil || header.recordingID == recordID {
            do {
                try await restoreLocalRecord(header)
            } catch {
                failed(header, detail: "보관된 기록을 확인하지 못했어요. 저장 상태를 확인해주세요.")
            }
        }
    }

    func refreshFailedVoiceCapture(experimentID: UUID, recordID: UUID) async {
        guard records[recordID]?.phase == .failed,
              !invalidatedVoiceStarts.contains(recordID),
              !transfer.isCancellationPending(recordingID: recordID) else { return }
        do {
            guard let header = try await archive.headers().first(where: {
                $0.experimentID == experimentID && $0.recordingID == recordID
            }), recorder.activeRecording != header else { return }
            let local = try await archive.statusEnsuringArchive(header)
            let remote = try await archive.remoteReceipt(header)
            var record = try await voiceWithLocalStatus(header, local: local, forceRefresh: true)
            guard records[recordID]?.phase == .failed,
                  !invalidatedVoiceStarts.contains(recordID),
                  !transfer.isCancellationPending(header) else { return }
            if local.isCancelled {
                record.phase = .cancelled
            } else if WatchRecordPresentation.isEmptyVoiceCapture(
                local: local, remote: remote, hasActiveCapture: recorder.activeRecording != nil
            ) {
                record.captureRejectedBeforeStart = true
            }
            publish(record)
        } catch {
            guard var record = records[recordID], record.phase == .failed,
                  !invalidatedVoiceStarts.contains(recordID),
                  !transfer.isCancellationPending(recordingID: recordID) else { return }
            record.captureCompleteConfirmed = false
            record.captureRejectedBeforeStart = false
            publish(record)
        }
    }

    private func restoreLocalRecord(_ header: WatchAudioHeader) async throws {
        let local = try await archive.statusEnsuringArchive(header)
        let remote = try await archive.remoteReceipt(header)
        var record = try await voiceWithLocalStatus(header, local: local, forceRefresh: true)
        if transfer.isCancellationPending(header) {
            record.phase = .saving
            record.detail = "녹음 취소를 확인하고 있어요."
        } else if recorder.activeRecording == header {
            record.phase = .capturing
        } else if local.isCancelled {
            record.phase = .cancelled
        } else if local.savedRecordID == header.recordingID {
            verifiedSavedReceipts.removeValue(forKey: header.recordingID)
            record.requiresSavedVerification = true
            record.phase = .saving
            record.detail = "iPhone의 저장 원본을 다시 확인하고 있어요."
        } else if local.manifest != nil {
            record.phase = .transferring
        } else {
            record.phase = .failed
            if WatchRecordPresentation.isEmptyVoiceCapture(
                local: local, remote: remote, hasActiveCapture: recorder.activeRecording != nil
            ) {

                record.captureRejectedBeforeStart = true
                record.detail = "저장된 음성 구간이 없어요. 다시 녹음해주세요."
            } else {
                record.detail = "보관된 구간의 상태를 확인해주세요."
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
        if local.savedRecordID == header.recordingID {

            requestSavedVerification(header)
        } else if let remote {
            await receiveAudio(remote)
        }
    }

    @discardableResult
    func requestSavedVerification(_ header: WatchAudioHeader) -> Task<Void, Never> {
        if let task = savedVerificationTasks[header.recordingID] { return task }
        let task = Task { [weak self] in
            guard let self else { return }
            defer { self.savedVerificationTasks[header.recordingID] = nil }
            self.retentionCache.removeValue(forKey: header.recordingID)
            do {
                let receipt = try await self.transfer.verifySaved(header)
                await self.receiveVerifiedSaved(receipt)
            } catch {
                self.retentionCache.removeValue(forKey: header.recordingID)
                let retention = try? await self.archive.localRetention(header)
                guard !self.transfer.isCancellationPending(header),
                      self.records[header.recordingID]?.phase != .saved else { return }
                var record = self.voice(header)
                let local = retention.flatMap {
                    WatchLocalRetentionPolicy.assess(
                        $0, recordingActive: self.recorder.activeRecording == header
                    )
                }
                record.phase = .failed
                record.requiresSavedVerification = true
                record.originalRetained = local?.originalRetained ?? false
                record.captureCompleteConfirmed = local?.captureCompleteConfirmed ?? false
                record.captureRejectedBeforeStart = false
                record.canAutoSave = false
                record.detail = local == nil
                    ? "iPhone 저장과 Watch 보관 상태를 확인하지 못했어요. 다시 확인해주세요."
                    : "iPhone 저장 원본을 확인하지 못했어요. 연결을 확인한 뒤 다시 확인해주세요."
                self.publish(record)
            }
        }
        savedVerificationTasks[header.recordingID] = task
        return task
    }

    func reconcileUnresolvedSavedRecords() async {
        let headers: [WatchAudioHeader]
        do {
            headers = try await archive.headers()
        } catch {
            let unresolved = records.values.filter {
                $0.kind == .voice && $0.phase != .saved && $0.phase != .cancelled
            }
            for current in unresolved {
                var record = current
                record.phase = .failed
                record.originalRetained = false
                record.captureCompleteConfirmed = false
                record.captureRejectedBeforeStart = false
                record.canAutoSave = false
                record.detail = "보관된 기록의 상태를 확인하지 못했어요. 다시 확인해주세요."
                publish(record)
            }
            return
        }
        for header in headers {
            guard !Task.isCancelled else { return }
            guard records[header.recordingID]?.phase != .saved,
                  !transfer.isCancellationPending(header) else { continue }
            do {
                let local = try await archive.statusEnsuringArchive(header)
                guard local.savedRecordID == header.recordingID else { continue }
                await requestSavedVerification(header).value
            } catch {
                failed(header, detail: "보관된 기록의 상태를 확인하지 못했어요. 다시 확인해주세요.")
            }
        }
    }

    func receiveVerifiedSaved(_ receipt: WatchAudioReceipt) async {
        guard !transfer.isCancellationPending(receipt.header) else { return }
        retentionCache.removeValue(forKey: receipt.header.recordingID)
        verifiedSavedReceipts[receipt.header.recordingID] = receipt
        await receiveAudio(receipt)
    }

    func receiveAudio(_ receipt: WatchAudioReceipt) async {
        if transfer.isCancellationPending(receipt.header), !receipt.isCancelled { return }
        await processAudio(receipt)
    }

    private func processAudio(_ receipt: WatchAudioReceipt) async {
        do {
            let local = try await archive.statusEnsuringArchive(receipt.header)
            var record = try await voiceWithLocalStatus(receipt.header, local: local)
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
            if receipt.savedRecordID == receipt.header.recordingID {
                record = savedStatus(receipt, local: local, record: record)
            } else if receipt.isCancelled {
                record.phase = .cancelled
                record.detail = record.originalRetained
                    ? "취소 결과를 확인했어요. 보관된 구간이 있어요." : "취소 결과를 확인했어요."
            } else if recorder.activeRecording == receipt.header {
                record = capturing(record)
            } else if let failure = receipt.failure {
                record.phase = .failed
                record.detail = failure == .recognitionUnavailable
                    ? "전사할 수 없어요. iPhone 권한·언어 설정과 연결을 확인해주세요."
                    : "기록 처리를 완료하지 못했어요. 보관 상태를 확인해주세요."
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
            failed(receipt.header, detail: "수신·저장 확인을 대조하지 못했어요. 보관 상태를 확인해주세요.")
        }
    }

    private func savedStatus(
        _ receipt: WatchAudioReceipt, local: WatchAudioReceipt, record: WatchRecordPresentation
    ) -> WatchRecordPresentation {
        var result = record
        if WatchSavedReceiptPolicy.permitsSaved(
            receipt: receipt,
            verified: verifiedSavedReceipts[receipt.header.recordingID],
            local: local
        ) {
            result.phase = .saved
            result.requiresSavedVerification = false
            result.detail = nil
        } else {
            verifiedSavedReceipts.removeValue(forKey: receipt.header.recordingID)
            requestSavedVerification(receipt.header)
            result.phase = .saving
            result.requiresSavedVerification = true
            result.detail = "iPhone의 저장 원본을 다시 확인하고 있어요."
        }
        return result
    }

    private func capturing(_ existing: WatchRecordPresentation) -> WatchRecordPresentation {
        var record = existing
        record.phase = .capturing
        record.captureCompleteConfirmed = false
        record.detail = nil
        return record
    }

    private func voiceWithLocalStatus(
        _ header: WatchAudioHeader, local: WatchAudioReceipt, forceRefresh: Bool = false
    ) async throws -> WatchRecordPresentation {
        let retention: WatchAudioLocalRetention
        if !forceRefresh, let cached = retentionCache[header.recordingID], cached.status == local {
            retention = cached.retention
        } else {
            retention = try await archive.localRetention(header)
            retentionCache[header.recordingID] = RetentionCacheEntry(
                status: local, retention: retention
            )
        }
        guard let local = WatchLocalRetentionPolicy.assess(
            retention, recordingActive: recorder.activeRecording == header
        ) else { throw WatchAudioError.invalidAudio }
        var record = voice(header)
        record.originalRetained = local.originalRetained
        record.captureCompleteConfirmed = local.captureCompleteConfirmed
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
        record.originalRetained = false
        record.captureCompleteConfirmed = false
        record.captureRejectedBeforeStart = false
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
