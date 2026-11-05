import Foundation
import LabcordShared
import SwiftData

@MainActor
final class ExperimentResultRepository {
    static let shared = ExperimentResultRepository()

    private let store = ExperimentStore.shared
    private let mediaStore = MediaRecordStore.shared

    private init() {}

    func loadResultDetail(id: UUID) throws -> ExperimentResultDetail? {
        let context = try store.makeContext()
        guard let experiment = try store.find(id: id, in: context) else { return nil }
        try mediaStore.repairPhotoFileExtensions(in: experiment, context: context)
        return Self.resultDetail(experiment)
    }

    func updateTitle(id: UUID, title: String) throws -> ExperimentResultDetail {
        let context = try store.makeContext()
        guard let experiment = try store.find(id: id, in: context) else {
            throw ExperimentStore.StoreError.experimentNotFound
        }
        experiment.title = title
        try context.save()
        return Self.resultDetail(experiment)
    }

    func updateRecordContent(
        experimentID: UUID,
        recordID: UUID,
        note: String,
        transcript: String?,
        timerEventID: String?
    ) throws -> ExperimentResultDetail {
        let context = try store.makeContext()
        guard let experiment = try store.find(id: experimentID, in: context) else {
            throw ExperimentStore.StoreError.experimentNotFound
        }
        guard let record = experiment.records.first(where: { $0.id == recordID }) else {
            throw RecordError.notFound
        }
        let savedNote = String(note.prefix(300))
        if record.type == .timer {
            guard let timerEventID else { throw RecordError.timerEventNotFound }
            if timerEventID == "timer-start-\(record.id)" {
                record.note = savedNote
            } else {
                let isEnd = timerEventID == "timer-end-\(record.id)"
                    && record.timerEndedAt != nil
                let isPauseEvent = record.timerPauses.contains { pause in
                    timerEventID == "timer-pause-\(pause.id)"
                        || (pause.resumedAt != nil && timerEventID == "timer-resume-\(pause.id)")
                }
                guard isEnd || isPauseEvent else { throw RecordError.timerEventNotFound }

                guard var notes = Self.timerEventNotes(for: record) else {
                    throw RecordError.invalidTimerEventNotes
                }
                if savedNote.isEmpty {
                    notes.removeValue(forKey: timerEventID)
                } else {
                    notes[timerEventID] = savedNote
                }
                record.timerEventNotesData = notes.isEmpty
                    ? nil : try JSONEncoder().encode(notes)
            }
        } else {
            record.note = savedNote
        }
        if record.type == .audio, let transcript {
            record.transcript = transcript
        }
        try context.save()
        return Self.resultDetail(experiment)
    }

    func deleteRecord(
        experimentID: UUID,
        recordID: UUID,
        entryID: String
    ) throws -> ExperimentResultDetail {
        let context = try store.makeContext()
        guard let experiment = try store.find(id: experimentID, in: context) else {
            throw ExperimentStore.StoreError.experimentNotFound
        }
        guard let record = experiment.records.first(where: { $0.id == recordID }) else {
            throw RecordError.notFound
        }
        if record.type == .timer {
            let isTimerEntry = Self.resultDetail(experiment).timeline.contains { entry in
                guard entry.id == entryID, case let .timer(entryRecord, _) = entry.kind else {
                    return false
                }
                return entryRecord.id == recordID
            }
            guard isTimerEntry else { throw RecordError.timerEventNotFound }
            guard var hiddenIDs = Self.hiddenTimerEventIDs(for: record),
                  var notes = Self.timerEventNotes(for: record) else {
                throw RecordError.invalidTimerEventNotes
            }
            hiddenIDs.insert(entryID)
            record.hiddenTimerEventIDsData = try JSONEncoder().encode(hiddenIDs.sorted())
            if entryID == "timer-start-\(recordID)" {
                record.note = ""
            } else {
                notes.removeValue(forKey: entryID)
                record.timerEventNotesData = notes.isEmpty
                    ? nil : try JSONEncoder().encode(notes)
            }
            try context.save()
            return Self.resultDetail(experiment)
        }
        guard entryID == "record-\(recordID)" else { throw RecordError.notFound }
        let filePath = record.filePath
        experiment.records.removeAll { $0.id == recordID }
        context.delete(record)
        try context.save()

        if let filePath {
            let url = URL.applicationSupportDirectory.appending(path: filePath)
            try? FileManager.default.removeItem(at: url)
        }
        return Self.resultDetail(experiment)
    }

    private enum RecordError: Error {
        case notFound
        case timerEventNotFound
        case invalidTimerEventNotes
    }

    private static func timerEventNotes(for record: ExperimentRecord) -> [String: String]? {
        guard let data = record.timerEventNotesData else { return [:] }
        return try? JSONDecoder().decode([String: String].self, from: data)
    }

    private static func hiddenTimerEventIDs(for record: ExperimentRecord) -> Set<String>? {
        guard let data = record.hiddenTimerEventIDsData else { return [] }
        return try? Set(JSONDecoder().decode([String].self, from: data))
    }

    private static func resultDetail(_ experiment: Experiment) -> ExperimentResultDetail {
        ExperimentResultDetail(
            id: experiment.id,
            title: experiment.title,
            createdAt: experiment.createdAt,
            startedAt: experiment.startedAt,
            endedAt: experiment.endedAt,
            status: experiment.status,
            mode: experiment.mode,
            procedure: experiment.procedure.map {
                ExperimentResultDetail.Procedure(
                    timerSeconds: $0.timerSeconds,
                    materials: $0.materials,
                    samples: $0.samples,
                    glossaryTerms: $0.glossaryTerms,
                    units: $0.units
                )
            },
            pauses: experiment.pauses.map {
                ExperimentResultDetail.PauseEntry(
                    id: $0.id,
                    pausedAt: $0.pausedAt,
                    resumedAt: $0.resumedAt
                )
            },
            records: experiment.records.map(recordDetail),
            statusHistory: experiment.statusHistory.sorted { $0.date < $1.date }.map {
                ExperimentResultDetail.StatusEntry(
                    id: $0.id,
                    status: $0.status,
                    date: $0.date
                )
            }
        )
    }

    private static func recordDetail(_ record: ExperimentRecord) -> ExperimentResultDetail.Record {
        ExperimentResultDetail.Record(
            id: record.id,
            type: record.type,
            recordedAt: record.recordedAt,
            note: record.note,
            filePath: record.filePath,
            transcript: record.transcript,
            timerEventNotes: timerEventNotes(for: record) ?? [:],
            hiddenTimerEventIDs: hiddenTimerEventIDs(for: record) ?? [],
            timerDurationSeconds: record.timerDurationSeconds,
            timerEndedAt: record.timerEndedAt,
            timerPauses: record.timerPauses.map {
                ExperimentResultDetail.PauseEntry(
                    id: $0.id,
                    pausedAt: $0.pausedAt,
                    resumedAt: $0.resumedAt
                )
            }
        )
    }
}
