import Foundation
import LabcordShared

extension PhoneWatchExperimentCoordinator {
    /// 영구 저장된 사진·영상만 재구성하고 미저장 촬영은 다시 실행하지 않는다.
    func restoreSavedRecords(_ experimentID: UUID) throws {
        guard let detail = try client.loadResultDetail(experimentID) else {
            try restoreMediaJournal(experimentID, savedIDs: [])
            return
        }
        guard detail.id == experimentID else { throw WatchExperimentError.duplicateConflict }
        var savedIDs: Set<UUID> = []
        for record in detail.records {
            if let saved = savedMedia(record) {
                _ = try publishRecord(saved, experimentID: experimentID)
                savedIDs.insert(record.id)
            }
        }
        try restoreMediaJournal(experimentID, savedIDs: savedIDs)
    }

    func handleSavedRecord(_ command: WatchExperimentCommand) throws -> Bool {
        guard [.confirmRecord, .cancelRecord].contains(command.operation),
              let saved = try savedRecord(command) else { return false }
        if command.operation == .cancelRecord { throw WatchExperimentError.invalidState }
        recordResults[command.requestID] = saved
        return true
    }

    func savedRecord(_ command: WatchExperimentCommand) throws -> WatchRecordSnapshot? {
        guard let experimentID = command.experimentID, let targetID = command.targetID,
              let detail = try client.loadResultDetail(experimentID) else { return nil }
        guard detail.id == experimentID else { throw WatchExperimentError.duplicateConflict }
        guard let record = detail.records.first(where: { $0.id == targetID }),
              record.type == .photo || record.type == .video else { return nil }
        guard let saved = savedMedia(record) else { throw WatchExperimentError.storageFailed }
        return try publishRecord(saved, experimentID: experimentID)
    }

    private func savedMedia(_ record: ExperimentResultDetail.Record) -> WatchRecordSnapshot? {
        let kind: WatchRecordSnapshot.Kind
        switch record.type {
        case .photo: kind = .photo
        case .video: kind = .video
        default: return nil
        }
        guard let path = record.filePath, !path.isEmpty else { return nil }
        let root = URL.applicationSupportDirectory.standardizedFileURL
        let url = root.appending(path: path).standardizedFileURL
        guard url.path.hasPrefix(root.path + "/") else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else { return nil }
        return WatchRecordSnapshot(
            id: record.id, kind: kind, phase: .saved, startedAt: record.recordedAt,
            canAutoSave: false, originalRetained: true
        )
    }
}
