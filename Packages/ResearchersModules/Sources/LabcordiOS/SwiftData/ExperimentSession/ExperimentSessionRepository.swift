import Foundation
import LabcordShared
import SwiftData

@MainActor
final class ExperimentSessionRepository {
    static let shared = ExperimentSessionRepository()

    private let store = ExperimentStore.shared
    private let mediaStore = MediaRecordStore.shared
    private let timerVisibility = WatchTimerVisibilityStore()

    private init() {}

    func enterSessionAndLoadDetail(id: UUID) throws -> ExperimentSessionDetail? {
        try loadDetail(id: id, recordEntry: true)
    }

    private func loadDetail(id: UUID, recordEntry: Bool) throws -> ExperimentSessionDetail? {
        try recoverTimerDeletions(experimentID: id)
        let context = try store.makeContext()
        guard let experiment = try store.find(id: id, in: context) else { return nil }

        let enteredAt = Date.now
        let timerSeconds = experiment.mode == .procedure
            ? experiment.procedure?.timerSeconds ?? []
            : []
        let procedure = experiment.mode == .procedure ? experiment.procedure : nil
        let speechContextualStrings = (procedure?.materials ?? [])
            + (procedure?.samples ?? [])
            + (procedure?.glossaryTerms ?? [])
            + (procedure?.units ?? [])
        let vocabulary = SpeechSessionVocabulary.usingCachedReadings(for: speechContextualStrings)
        let timers = activeTimers(in: experiment, at: enteredAt, persistExpiry: recordEntry)
        if recordEntry {
            if experiment.status != .completed, experiment.startedAt == nil {
                experiment.startedAt = enteredAt
            }
            experiment.recordEntry(at: enteredAt)
            try context.save()
        }
        return ExperimentSessionDetail(
            title: experiment.title,
            timerSeconds: timerSeconds,
            mode: experiment.mode,
            timers: timers,
            speechTerms: speechContextualStrings,
            speechUnits: procedure?.units ?? [],
            speechContextualStrings: vocabulary.contextualStrings,
            speechPhoneticReplacements: vocabulary.replacements
        )
    }

    func watchState(id: UUID) throws -> WatchExperimentState? {
        try recoverTimerDeletions(experimentID: id)
        let context = try store.makeContext()
        guard let experiment = try store.find(id: id, in: context),
              let detail = try loadDetail(id: id, recordEntry: false) else { return nil }
        return WatchExperimentState(
            experiment: WatchExperimentSummary(
                id: id, title: experiment.title, status: experiment.status
            ),
            detail: ExperimentSessionDetail(
                title: detail.title, timerSeconds: detail.timerSeconds, mode: detail.mode,
                timers: try watchTimers(in: experiment, at: .now),
                speechContextualStrings: detail.speechContextualStrings
            )
        )
    }

    func applyWatchTimer(_ command: WatchExperimentCommand) throws {
        guard let experimentID = command.experimentID else {
            throw WatchExperimentError.invalidPayload
        }
        try recoverTimerDeletions(experimentID: experimentID)
        let context = try store.makeContext()
        guard let experiment = try store.find(id: experimentID, in: context) else {
            throw ExperimentStore.StoreError.experimentNotFound
        }
        let now = Date()
        let timers = try watchTimers(in: experiment, at: now)
        if command.operation == .startTimer,
           let existing = experiment.records.first(where: { $0.id == command.requestID }) {
            guard existing.type == .timer,
                  existing.timerDurationSeconds == command.durationSeconds else {
                throw WatchExperimentError.duplicateConflict
            }

            return
        }
        if command.operation == .deleteTimer, let timerID = command.targetID,
           try timerVisibility.dismissedTimerIDs(experimentID: experimentID).contains(timerID) {
            guard experiment.records.contains(where: {
                $0.id == timerID && $0.type == .timer
            }) else {
                throw WatchExperimentError.invalidState
            }
            return
        }
        let mutation = try WatchTimerMutation.prepare(command, timers: timers, at: now)
        if command.operation == .deleteTimer, let timerID = command.targetID {
            try timerVisibility.beginDeletion(
                experimentID: experimentID, timerID: timerID, endedAt: now
            )
        }
        for change in mutation.changes {
            upsertTimer(change.timer, endedAt: change.endedAt, in: experiment)
        }
        if !mutation.changes.isEmpty { try context.save() }
        if command.operation == .deleteTimer, let timerID = command.targetID {

            try dismissWatchTimer(experimentID: experimentID, timerID: timerID)
        }
    }

    func dismissWatchTimer(experimentID: UUID, timerID: UUID) throws {
        let context = try store.makeContext()
        guard let experiment = try store.find(id: experimentID, in: context) else {
            throw ExperimentStore.StoreError.experimentNotFound
        }
        guard let record = experiment.records.first(where: {
            $0.id == timerID && $0.type == .timer
        }),
              record.timerEndedAt != nil else {
            throw WatchExperimentError.invalidState
        }
        try timerVisibility.dismiss(experimentID: experimentID, timerID: timerID)
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
        upsertTimer(timer, endedAt: endedAt, in: experiment)
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

    private func watchTimers(
        in experiment: Experiment, at date: Date
    ) throws -> [ExperimentTimer] {
        let dismissed = try timerVisibility.dismissedTimerIDs(experimentID: experiment.id)
        return try experiment.records
            .filter { $0.type == .timer && !dismissed.contains($0.id) }
            .map { record in
                guard let duration = record.timerDurationSeconds,
                      duration > 0, duration <= Int(Int32.max) else {
                    throw WatchExperimentError.invalidPayload
                }
                var timer = ExperimentTimer(
                    id: record.id, durationSeconds: duration, startedAt: record.recordedAt,
                    pauseIntervals: record.timerPauses.sorted { $0.pausedAt < $1.pausedAt }.map {
                        ExperimentTimer.PauseInterval(
                            id: $0.id, pausedAt: $0.pausedAt, resumedAt: $0.resumedAt
                        )
                    },
                    finishedAt: record.timerEndedAt
                )
                timer.finishIfNeeded(at: date)
                return timer
            }
            .sorted {
                if $0.startedAt != $1.startedAt { return $0.startedAt < $1.startedAt }
                return $0.id.uuidString < $1.id.uuidString
            }
    }

    private func activeTimers(
        in experiment: Experiment, at date: Date, persistExpiry: Bool = true
    ) -> [ExperimentTimer] {
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
                if persistExpiry, record.timerEndedAt == nil, let finishedAt = timer.finishedAt {
                    record.timerEndedAt = finishedAt
                }
                return timer.status == .finished ? nil : timer
            }
            .sorted { $0.startedAt < $1.startedAt }
    }
}

private extension ExperimentSessionRepository {
    func upsertTimer(
        _ timer: ExperimentTimer, endedAt: Date?, in experiment: Experiment
    ) {
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
        record.timerEndedAt = record.timerEndedAt ?? timer.finishedAt ?? endedAt
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
    }
}

extension ExperimentSessionRepository {
    func beginTimerDeletion(experimentID: UUID, timerID: UUID, endedAt: Date) throws {
        let context = try store.makeContext()
        guard let experiment = try store.find(id: experimentID, in: context),
              experiment.records.contains(where: { $0.id == timerID && $0.type == .timer }) else {
            throw WatchExperimentError.invalidState
        }
        try timerVisibility.beginDeletion(
            experimentID: experimentID, timerID: timerID, endedAt: endedAt
        )
    }

    private func recoverTimerDeletions(experimentID: UUID) throws {
        let pending = try timerVisibility.pendingDeletions(experimentID: experimentID)
        guard !pending.isEmpty else { return }
        let context = try store.makeContext()
        guard let experiment = try store.find(id: experimentID, in: context) else {
            throw ExperimentStore.StoreError.experimentNotFound
        }
        for (id, endedAt) in pending {
            guard let record = experiment.records.first(where: {
                $0.id == id && $0.type == .timer
            }) else { throw WatchExperimentError.invalidState }
            record.timerEndedAt = record.timerEndedAt ?? endedAt
        }
        try context.save()
        for id in pending.keys {
            try timerVisibility.dismiss(experimentID: experimentID, timerID: id)
        }
    }

}
