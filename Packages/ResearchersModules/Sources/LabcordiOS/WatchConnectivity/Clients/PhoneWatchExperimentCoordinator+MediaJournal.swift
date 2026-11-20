import Foundation
import LabcordShared

extension PhoneWatchExperimentCoordinator {
    func validateCameraPayload(_ command: WatchExperimentCommand) throws {
        guard command.experimentID != nil else { throw WatchExperimentError.invalidPayload }
        guard command.expectedRevision != nil else { throw WatchExperimentError.staleRevision }
        switch command.operation {
        case .takePhoto, .startVideo, .stopVideo:
            if let requestedKind = command.recordKind, requestedKind != mediaKind(command) {
                throw WatchExperimentError.invalidPayload
            }
            if command.operation != .stopVideo { return }
        default:
            break
        }
        guard command.targetID != nil else { throw WatchExperimentError.invalidPayload }
    }

    func validateCameraTarget(_ command: WatchExperimentCommand) throws {
        let id = command.targetID ?? command.requestID
        let record = recordSnapshots[id]
        if let record, record.experimentID != command.experimentID || record.kind == .audio {
            throw WatchExperimentError.invalidPayload
        }
        switch command.operation {
        case .takePhoto, .startVideo:
            guard record == nil, captureCommand(for: command, targetID: id) == nil else {
                throw WatchExperimentError.duplicateConflict
            }
        case .stopVideo, .confirmRecord, .cancelRecord:
            let origin = captureCommand(for: command, targetID: id)
            let kind = record?.kind ?? origin.flatMap(mediaKind)
            guard let kind else { throw WatchExperimentError.invalidState }
            let claimedKind = command.operation == .stopVideo ? .video : command.recordKind
            guard claimedKind == nil || claimedKind == kind else {
                throw WatchExperimentError.invalidPayload
            }
        default:
            break
        }
    }

    func recoverStoppedVideo(_ command: WatchExperimentCommand) -> Bool {
        guard command.operation == .stopVideo, let id = command.targetID,
              let record = recordSnapshots[id] else { return false }
        if [.previewing, .review, .saving, .saved].contains(record.phase) {
            recordResults[command.requestID] = record
            return true
        }
        if record.phase == .failed, record.originalRetained == true {
            recordResults[command.requestID] = record
            return true
        }
        return false
    }

    func validateMediaRecord(
        _ record: WatchRecordSnapshot, requestID: UUID, experimentID: UUID
    ) throws {
        guard record.kind != .audio else { return }
        guard let entry = requests[requestID] ?? journal?.entries[requestID],
              entry.command.experimentID == experimentID,
              (entry.command.targetID ?? entry.command.requestID) == record.id,
              record.experimentID == nil || record.experimentID == experimentID,
              (mediaKind(entry.command) ?? entry.response.record?.kind) == record.kind else {
            throw WatchExperimentError.duplicateConflict
        }
    }

    func updateMediaJournal(
        _ response: WatchExperimentResponse, record: WatchRecordSnapshot, experimentID: UUID
    ) throws {
        guard record.kind != .audio else { return }
        try validateMediaRecord(record, requestID: response.requestID, experimentID: experimentID)
        guard let entry = requests[response.requestID] ?? journal?.entries[response.requestID],
              journal != nil else { throw WatchExperimentError.storageFailed }
        if let previous = entry.response.record,
           (previous.revision ?? 0) >= (record.revision ?? 0) { return }
        let outcome = mediaOutcome(for: entry.command.operation, record: record)
        let result = WatchExperimentResponse(
            requestID: response.requestID, phase: outcome?.0 ?? response.phase,
            snapshot: response.snapshot ?? entry.response.snapshot,
            error: outcome == nil ? response.error : outcome?.1, record: record,
            screen: response.screen ?? entry.response.screen
        )
        try journal?.save(entry.command, response: result)
        if requests[response.requestID] != nil {
            requests[response.requestID]?.response = result
        }
    }

    func restoreMediaJournal(_ experimentID: UUID, savedIDs: Set<UUID>) throws {
        var latest: [UUID: WatchExperimentRequestJournal.Entry] = [:]
        for entry in mediaEntries() where entry.command.experimentID == experimentID {
            guard let record = entry.response.record, record.kind != .audio,
                  !savedIDs.contains(record.id) else { continue }
            try validateMediaRecord(
                record, requestID: entry.command.requestID, experimentID: experimentID
            )
            if let previous = latest[record.id]?.response.record {
                let oldRevision = previous.revision ?? 0
                let newRevision = record.revision ?? 0
                if oldRevision > newRevision { continue }
                if oldRevision == newRevision,
                   mediaPriority(previous.phase) >= mediaPriority(record.phase) { continue }
            }
            latest[record.id] = entry
        }
        for entry in latest.values {
            guard let record = entry.response.record else { continue }
            let restarted = requests[entry.command.requestID] == nil
            if restarted, record.phase != .cancelled, record.error != .resultUnknown,
               record.phase != .failed || record.originalRetained != false {
                let unknown = WatchRecordSnapshot(
                    id: record.id, kind: record.kind, phase: .failed, startedAt: record.startedAt,
                    canAutoSave: false, error: .resultUnknown
                )
                let value = try publishRecord(unknown, experimentID: experimentID)
                try updateMediaJournal(WatchExperimentResponse(
                    requestID: entry.command.requestID, phase: .failed, error: .resultUnknown
                ), record: value, experimentID: experimentID)
            } else {
                _ = try publishRecord(
                    record, experimentID: experimentID, restoringRecord: restarted
                )
            }
        }
    }

    func cancelUnavailableMedia(_ command: WatchExperimentCommand) throws -> Bool {
        guard command.operation == .cancelRecord, let experimentID = command.experimentID,
              let targetID = command.targetID, let record = recordSnapshots[targetID],
              record.experimentID == experimentID, record.kind != .audio,
              record.phase == .cancelled
                || record.phase == .failed && record.originalRetained == false
                    && record.error != .resultUnknown else {
            return false
        }
        if record.phase == .cancelled {
            recordResults[command.requestID] = record
            return true
        }
        if let activeID = executing, let active = requests[activeID]?.command,
           active.requestID != command.requestID,
           [.takePhoto, .startVideo, .stopVideo].contains(active.operation),
           active.experimentID == experimentID, active.targetID == targetID { return false }

        if try savedRecord(command) != nil { throw WatchExperimentError.invalidState }
        let cancelled = WatchRecordSnapshot(
            id: targetID, kind: record.kind, phase: .cancelled, startedAt: record.startedAt,
            canAutoSave: false, originalRetained: false
        )
        let value = try publishRecord(cancelled, experimentID: experimentID)
        recordResults[command.requestID] = value
        return true
    }

    func latestMediaResult(
        _ command: WatchExperimentCommand, response: WatchExperimentResponse
    ) -> WatchExperimentResponse {
        var result = response
        if let latest = journal?.entries[command.requestID]?.response,
           let record = latest.record, record.kind != .audio,
           (record.revision ?? 0) > (result.record?.revision ?? 0) {
            result = WatchExperimentResponse(
                requestID: response.requestID, phase: latest.phase,
                snapshot: response.snapshot ?? latest.snapshot, error: latest.error,
                startToken: response.startToken, record: record,
                screen: response.screen ?? latest.screen
            )
        }
        guard command.isCameraCommand, let kind = mediaKind(command), kind != .audio,
              result.phase != .failed || result.error == .resultUnknown else { return result }
        let targetID = command.targetID ?? command.requestID
        guard let record = recordSnapshots[targetID], record.kind == kind,
              record.experimentID == command.experimentID,
              (record.revision ?? 0) >= (result.record?.revision ?? 0) else { return result }
        if result.record == nil, result.phase == .received || result.phase == .processing {
            guard requests[command.requestID] == nil, targetID == command.requestID,
                  [.takePhoto, .startVideo].contains(command.operation), record.phase == .saved
            else { return result }
        }
        let outcome = mediaOutcome(for: command.operation, record: record)
        return WatchExperimentResponse(
            requestID: response.requestID, phase: outcome?.0 ?? result.phase,
            snapshot: result.snapshot, error: outcome == nil ? result.error : outcome?.1,
            startToken: result.startToken, record: record, screen: result.screen
        )
    }

    private func mediaOutcome(
        for operation: WatchExperimentCommand.Operation, record: WatchRecordSnapshot
    ) -> (WatchExperimentResponse.Phase, WatchExperimentError?)? {
        switch (operation, record.phase) {
        case (.cancelRecord, .saved), (.confirmRecord, .cancelled), (.stopVideo, .cancelled):
            return (.failed, .invalidState)
        case (.cancelRecord, .cancelled), (.confirmRecord, .saved),
             (.stopVideo, .previewing), (.stopVideo, .review), (.stopVideo, .saved),
             (.takePhoto, .review), (.startVideo, .recording),
             (.startVideo, .previewing), (.startVideo, .review),
             (.takePhoto, .saved), (.startVideo, .saved),
             (.takePhoto, .cancelled), (.startVideo, .cancelled):
            return (.completed, nil)
        case (_, .failed):
            return (.failed, record.error ?? .resultUnknown)
        default:
            return nil
        }
    }

    private func mediaPriority(_ phase: WatchRecordSnapshot.Phase) -> Int {
        switch phase {
        case .saved: 4
        case .cancelled: 3
        case .failed: 2
        default: 1
        }
    }

    private func mediaEntries() -> [WatchExperimentRequestJournal.Entry] {
        var entries = journal?.entries ?? [:]
        for (id, entry) in requests where entry.response.record != nil || entries[id] == nil {
            entries[id] = entry
        }
        return entries.values.filter { entry in
            [.takePhoto, .startVideo, .stopVideo, .confirmRecord, .cancelRecord]
                .contains(entry.command.operation)
        }
    }

    func mediaKind(_ command: WatchExperimentCommand) -> WatchRecordSnapshot.Kind? {
        switch command.operation {
        case .takePhoto: return .photo
        case .startVideo, .stopVideo: return .video
        case .confirmRecord, .cancelRecord:
            guard let targetID = command.targetID else { return nil }
            if let previous = recordSnapshots[targetID],
               previous.experimentID == command.experimentID { return previous.kind }
            return captureCommand(for: command, targetID: targetID).flatMap(mediaKind)
                ?? command.recordKind
        default: return nil
        }
    }

    private func captureCommand(
        for command: WatchExperimentCommand, targetID: UUID
    ) -> WatchExperimentCommand? {
        mediaEntries().map(\.command).first { candidate in
            candidate.requestID != command.requestID
                && candidate.experimentID == command.experimentID
                && (candidate.targetID ?? candidate.requestID) == targetID
                && [.takePhoto, .startVideo].contains(candidate.operation)
        }
    }
}
