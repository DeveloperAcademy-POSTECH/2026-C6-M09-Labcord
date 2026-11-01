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
