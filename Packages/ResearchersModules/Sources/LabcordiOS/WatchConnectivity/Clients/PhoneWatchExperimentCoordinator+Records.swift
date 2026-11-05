import Foundation
import LabcordShared

extension PhoneWatchExperimentCoordinator {
    public func configureRecordHandling() {
        guard recordHandler == nil else { return }
        recordHandler = { [weak self] command in
            guard let self else {
                throw WatchDefinitiveRejection(error: .phoneBusy)
            }
            if let id = command.experimentID, let targetID = command.targetID,
               [.confirmRecord, .cancelRecord].contains(command.operation),
               try await PhoneWatchAudioService.shared.containsRecord(
                experimentID: id, recordID: targetID
               ) {
                let response = try await PhoneWatchAudioService.shared.handleRecordCommand(command)
                if let error = response.error { throw error }
                if let record = response.record { recordResults[command.requestID] = record }
                return
            }
            if try handleSavedRecord(command) { return }
            if try cancelUnavailableMedia(command) { return }
            if [.startTimer, .pauseTimer, .resumeTimer, .deleteTimer].contains(command.operation),
               try shouldApplyTimerDirectly(command) {
                try client.applyWatchTimer(command)
                return
            }
            guard let commandSubscriber else {
                throw WatchDefinitiveRejection(error: .phoneBusy)
            }
            try await withCheckedThrowingContinuation { continuation in
                self.completions[command.requestID] = continuation
                commandSubscriber.yield(.command(command))
            }
        }
    }

    public func finishRecord(_ response: WatchExperimentResponse, experimentID: UUID) {
        do {
            var record = try response.record.map {
                try validateMediaRecord(
                    $0, requestID: response.requestID, experimentID: experimentID
                )
                return try publishRecord($0, experimentID: experimentID)
            }
            if response.error == nil, response.phase == .completed, record == nil,
               let command = requests[response.requestID]?.command,
               command.operation == .confirmRecord {
                guard let saved = try savedRecord(command) else {
                    throw WatchExperimentError.storageFailed
                }
                record = saved
            }
            if let record {
                try updateMediaJournal(response, record: record, experimentID: experimentID)
            }
            if let error = response.error {
                if isPreCaptureRejection(response) {
                    completions.removeValue(forKey: response.requestID)?
                        .resume(throwing: WatchDefinitiveRejection(error: error))
                    return
                }
                finish(response.requestID, error: error)
                return
            }
            guard response.phase == .completed || record != nil else { return }
            if let command = requests[response.requestID]?.command,
               command.operation == .deleteTimer, let id = command.targetID {
                try client.dismissWatchTimer(experimentID, id)
            }
            if completions[response.requestID] != nil {
                recordResults[response.requestID] = record
                finish(response.requestID)
            }
            refresh()
        } catch {
            finish(response.requestID, error: error as? WatchExperimentError ?? .storageFailed)
        }
    }

    private func isPreCaptureRejection(_ response: WatchExperimentResponse) -> Bool {
        guard response.phase == .failed, response.record == nil,
              let error = response.error, [.permissionDenied, .cameraUnavailable].contains(error),
              let command = requests[response.requestID]?.command else { return false }
        return [.takePhoto, .startVideo].contains(command.operation)
    }

    private func shouldApplyTimerDirectly(_ command: WatchExperimentCommand) throws -> Bool {
        guard visibleExperimentID == command.experimentID else { return true }
        guard command.operation == .deleteTimer, let id = command.experimentID else {
            return false
        }
        return try client.watchState(id)?.detail.timers.contains {
            $0.id == command.targetID && $0.status == .finished
        } == true
    }

    func publishRecord(
        _ record: WatchRecordSnapshot, experimentID: UUID
    ) throws -> WatchRecordSnapshot {
        guard record.experimentID == nil || record.experimentID == experimentID else {
            throw WatchExperimentError.duplicateConflict
        }
        if let previous = recordSnapshots[record.id] {
            guard previous.experimentID == experimentID, previous.kind == record.kind else {
                throw WatchExperimentError.duplicateConflict
            }
            if previous.phase == .saved { return previous }
            if previous.phase == .cancelled, record.phase != .saved { return previous }
            if let revision = record.revision, revision <= (previous.revision ?? 0) {
                return previous
            }
        }
        let value = record.withContext(experimentID: experimentID, revision: nil)
        if let previous = recordSnapshots[record.id],
           previous.withContext(experimentID: experimentID, revision: nil) == value {
            return previous
        }
        let identified = record.withContext(
            experimentID: experimentID, revision: try record.revision ?? nextRevision()
        )
        if let previous = recordSnapshots[record.id],
           previous.experimentID != experimentID || previous.kind != identified.kind {
            throw WatchExperimentError.duplicateConflict
        }
        recordSnapshots[record.id] = identified
        connectivity.records.publish(identified, session: connectivity.session)
        return identified
    }
}
