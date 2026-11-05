import Foundation
import LabcordShared

extension PhoneWatchExperimentCoordinator {
    func validateMediaRecord(
        _ record: WatchRecordSnapshot, requestID: UUID, experimentID: UUID
    ) throws {
        guard record.kind != .audio else { return }
        guard let entry = requests[requestID] ?? journal?.entries[requestID],
              entry.command.experimentID == experimentID,
              (entry.command.targetID ?? entry.command.requestID) == record.id,
              record.experimentID == nil || record.experimentID == experimentID,
              mediaKind(entry.command) == record.kind else {
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
        let saved = record.phase == .saved
        let result = WatchExperimentResponse(
            requestID: response.requestID, phase: saved ? .completed : response.phase,
            snapshot: response.snapshot ?? entry.response.snapshot,
            error: saved ? nil : response.error, record: record
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
            if restarted, record.phase != .cancelled,
               record.phase != .failed || record.originalRetained != false {
                let unknown = WatchRecordSnapshot(
                    id: record.id, kind: record.kind, phase: .failed, startedAt: record.startedAt,
                    canAutoSave: false, originalRetained: false, error: .resultUnknown
                )
                let value = try publishRecord(unknown, experimentID: experimentID)
                try updateMediaJournal(WatchExperimentResponse(
                    requestID: entry.command.requestID, phase: .failed, error: .resultUnknown
                ), record: value, experimentID: experimentID)
            } else {
                _ = try publishRecord(record, experimentID: experimentID)
            }
        }
    }

    func cancelUnavailableMedia(_ command: WatchExperimentCommand) throws -> Bool {
        guard command.operation == .cancelRecord, let experimentID = command.experimentID,
              let targetID = command.targetID, let record = recordSnapshots[targetID],
              record.experimentID == experimentID, record.kind != .audio,
              record.phase == .failed, record.originalRetained == false else { return false }
        if let activeID = executing, let active = requests[activeID]?.command,
           active.requestID != command.requestID,
           [.takePhoto, .startVideo, .stopVideo].contains(active.operation),
           active.experimentID == experimentID, active.targetID == targetID { return false }
        // 이미 저장된 기록인지 직전에 다시 확인한다. 원본 파일은 정리하지 않는다.
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
                startToken: response.startToken, record: record
            )
        }
        let targetID = command.targetID ?? command.requestID
        guard let record = recordSnapshots[targetID], record.kind != .audio,
              record.experimentID == command.experimentID,
              (record.revision ?? 0) > (result.record?.revision ?? 0) else { return result }
        let phase: WatchExperimentResponse.Phase
        let error: WatchExperimentError?
        switch record.phase {
        case .saved, .cancelled:
            phase = .completed
            error = nil
        case .failed:
            phase = .failed
            error = record.error ?? .resultUnknown
        default:
            phase = result.phase
            error = result.error
        }
        return WatchExperimentResponse(
            requestID: response.requestID, phase: phase, snapshot: result.snapshot,
            error: error, startToken: result.startToken, record: record
        )
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

    private func mediaKind(_ command: WatchExperimentCommand) -> WatchRecordSnapshot.Kind? {
        switch command.operation {
        case .takePhoto: return .photo
        case .startVideo, .stopVideo: return .video
        case .confirmRecord, .cancelRecord:
            guard let targetID = command.targetID else { return nil }
            if let previous = recordSnapshots[targetID],
               previous.experimentID == command.experimentID { return previous.kind }
            return mediaEntries().first { entry in
                entry.command.experimentID == command.experimentID
                    && (entry.command.targetID ?? entry.command.requestID) == targetID
                    && [.takePhoto, .startVideo].contains(entry.command.operation)
            }.map { $0.command.operation == .takePhoto ? .photo : .video }
        default: return nil
        }
    }
}
