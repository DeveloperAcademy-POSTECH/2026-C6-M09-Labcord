import Foundation
import LabcordShared
import SwiftData

@MainActor
final class ExperimentSessionRepository {
    static let shared = ExperimentSessionRepository()

    private let store = ExperimentStore.shared
    private let mediaStore = MediaRecordStore.shared

    private init() {}

    func loadDetail(id: UUID) throws -> ExperimentSessionDetail? {
        let context = try store.makeContext()
        guard let experiment = try store.find(id: id, in: context) else { return nil }

        let enteredAt = Date.now
        let timerSeconds = experiment.mode == .procedure
            ? experiment.procedure?.timerSeconds ?? []
            : []
        let timers = activeTimers(in: experiment, at: enteredAt)
        experiment.recordEntry(at: enteredAt)
        try context.save()
        return ExperimentSessionDetail(
            title: experiment.title,
            timerSeconds: timerSeconds,
            mode: experiment.mode,
            timers: timers
        )
    }

    func leaveSession(id: UUID, entryID: UUID, at date: Date) throws {
        let context = try store.makeContext()
        guard let experiment = try store.find(id: id, in: context) else {
            throw ExperimentStore.StoreError.experimentNotFound
        }
        _ = activeTimers(in: experiment, at: date)
        experiment.recordExit(at: date, entryID: entryID)
        try context.save()
    }

    func saveTimer(experimentID: UUID, timer: ExperimentTimer, endedAt: Date? = nil) throws {
        let context = try store.makeContext()
        guard let experiment = try store.find(id: experimentID, in: context) else {
            throw ExperimentStore.StoreError.experimentNotFound
        }

        let record: ExperimentRecord
        if let existing = experiment.records.first(where: { $0.id == timer.id }) {
            record = existing
        } else {
            record = ExperimentRecord(
                id: timer.id,
                type: .timer,
                recordedAt: timer.startedAt,
                note: "",
                timerDurationSeconds: timer.durationSeconds
            )
            experiment.records.append(record)
        }

        record.timerEndedAt = timer.finishedAt ?? endedAt
        for interval in timer.pauseIntervals {
            if let pause = record.timerPauses.first(where: { $0.id == interval.id }) {
                pause.resumedAt = interval.resumedAt
            } else {
                record.timerPauses.append(
                    Pause(
                        id: interval.id,
                        pausedAt: interval.pausedAt,
                        resumedAt: interval.resumedAt
                    )
                )
            }
        }
        try context.save()
    }

    func savePhoto(experimentID: UUID, id: UUID, recordedAt: Date, data: Data) throws {
        try mediaStore.savePhoto(
            experimentID: experimentID, id: id, recordedAt: recordedAt, data: data
        )
    }

    func saveVideo(experimentID: UUID, id: UUID, recordedAt: Date, sourceURL: URL) throws {
        try mediaStore.saveVideo(
            experimentID: experimentID, id: id, recordedAt: recordedAt, sourceURL: sourceURL
        )
    }

    func saveAudio(
        experimentID: UUID,
        id: UUID,
        recordedAt: Date,
        sourceURL: URL,
        transcript: String
    ) throws {
        try mediaStore.saveAudio(
            experimentID: experimentID,
            id: id,
            recordedAt: recordedAt,
            sourceURL: sourceURL,
            transcript: transcript
        )
    }

    func cancelVideoSave(experimentID: UUID, id: UUID, sourceURL: URL) throws {
        try mediaStore.cancelVideoSave(experimentID: experimentID, id: id, sourceURL: sourceURL)
    }

    func cancelAudioSave(experimentID: UUID, id: UUID, sourceURL: URL) throws {
        try mediaStore.cancelAudioSave(experimentID: experimentID, id: id, sourceURL: sourceURL)
    }

    func complete(id: UUID, at date: Date) throws {
        let context = try store.makeContext()
        guard let experiment = try store.find(id: id, in: context) else {
            throw ExperimentStore.StoreError.experimentNotFound
        }
        _ = activeTimers(in: experiment, at: date)
        for record in experiment.records
            where record.type == .timer && record.timerEndedAt == nil {
            record.timerEndedAt = date
        }
        experiment.complete(at: date)
        try context.save()
    }

    private func activeTimers(in experiment: Experiment, at date: Date) -> [ExperimentTimer] {
        experiment.records
            .filter { $0.type == .timer && $0.timerEndedAt == nil }
            .compactMap { record -> ExperimentTimer? in
                guard let duration = record.timerDurationSeconds else { return nil }
                var timer = ExperimentTimer(
                    id: record.id,
                    durationSeconds: duration,
                    startedAt: record.recordedAt,
                    pauseIntervals: record.timerPauses
                        .sorted { $0.pausedAt < $1.pausedAt }
                        .map {
                            ExperimentTimer.PauseInterval(
                                id: $0.id,
                                pausedAt: $0.pausedAt,
                                resumedAt: $0.resumedAt
                            )
                        },
                    finishedAt: record.timerEndedAt
                )
                timer.finishIfNeeded(at: date)
                if record.timerEndedAt == nil, let finishedAt = timer.finishedAt {
                    record.timerEndedAt = finishedAt
                }
                return timer.status == .finished ? nil : timer
            }
            .sorted { $0.startedAt < $1.startedAt }
    }
}
