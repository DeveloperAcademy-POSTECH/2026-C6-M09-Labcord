import Foundation
import LabcordShared
import SwiftData

@MainActor
final class ExperimentListRepository {
    static let shared = ExperimentListRepository()

    private let store = ExperimentStore.shared
    private let mediaStore = MediaRecordStore.shared

    private init() {}

    func load() throws -> [ExperimentListEntry] {
        let context = try store.makeContext()
        let experiments = try context.fetch(FetchDescriptor<Experiment>())
        let interrupted = experiments.filter { $0.status == .running }
        for experiment in interrupted {
            experiment.repairInterruptedRun(entryID: UUID())
        }
        if !interrupted.isEmpty { try context.save() }
        recoverInterruptedVoiceRecordings()
        let now = Date.now
        return experiments.map { Self.entry($0, at: now) }
    }

    func loadForWatch() throws -> [ExperimentListEntry] {
        let context = try store.makeContext()
        let experiments = try context.fetch(FetchDescriptor<Experiment>())
        let now = Date.now
        return experiments.map { Self.entry($0, at: now) }
    }

    func create(id: UUID, at date: Date) throws -> ExperimentListEntry {
        let context = try store.makeContext()
        if let existing = try store.find(id: id, in: context) {
            return Self.entry(existing)
        }

        let defaults = UserDefaults.standard
        let nextNumber = defaults.integer(forKey: "lastExperimentNumber") + 1
        let experiment = Experiment(
            id: id,
            title: "새 실험 (\(nextNumber))",
            createdAt: date,
            mode: .free,
        )

        context.insert(experiment)
        try context.save()

        defaults.set(nextNumber, forKey: "lastExperimentNumber")
        return Self.entry(experiment)
    }

    func createWithProtocol(
        id: UUID,
        at date: Date,
        title: String,
        procedure: ExperimentProtocol
    ) throws -> ExperimentListEntry {
        let context = try store.makeContext()
        if let existing = try store.find(id: id, in: context) {
            guard existing.mode == .procedure,
                  existing.title == title,
                  let saved = existing.procedure,
                  saved.timerSeconds == procedure.timerSeconds,
                  saved.materials == procedure.materials,
                  saved.samples == procedure.samples,
                  saved.glossaryTerms == procedure.glossaryTerms,
                  saved.units == procedure.units else {
                throw ExperimentCreationError.conflictingIdentifier
            }
            return Self.entry(existing)
        }

        let experiment = Experiment(
            id: id,
            title: title,
            createdAt: date,
            mode: .procedure,
            procedure: procedure
        )
        context.insert(experiment)
        try context.save()
        return Self.entry(experiment)
    }

    func delete(id: UUID) throws {
        let context = try store.makeContext()
        if let experiment = try store.find(id: id, in: context) {
            context.delete(experiment)
            try context.save()
        }
        try mediaStore.removeFiles(experimentID: id)
    }

    private static func entry(
        _ experiment: Experiment,
        at date: Date = .now
    ) -> ExperimentListEntry {
        ExperimentListEntry(
            id: experiment.id,
            title: experiment.title,
            createdAt: experiment.createdAt,
            status: .init(experiment.status),
            lastRunningTimerEndsAt: lastRunningTimerEndsAt(in: experiment, at: date)
        )
    }

    private static func lastRunningTimerEndsAt(in experiment: Experiment, at date: Date) -> Date? {
        experiment.records.compactMap { record -> Date? in
            guard record.type == .timer,
                  record.timerEndedAt == nil,
                  let duration = record.timerDurationSeconds else { return nil }
            let pauses = record.timerPauses
                .sorted { $0.pausedAt < $1.pausedAt }
                .map {
                    ExperimentTimer.PauseInterval(
                        id: $0.id,
                        pausedAt: $0.pausedAt,
                        resumedAt: $0.resumedAt
                    )
                }
            let timer = ExperimentTimer(
                id: record.id,
                durationSeconds: duration,
                startedAt: record.recordedAt,
                pauseIntervals: pauses
            )
            guard timer.status == .running, timer.remainingSeconds(at: date) > 0 else {
                return nil
            }
            let pausedDuration = pauses.reduce(0.0) { total, pause in
                total + (pause.resumedAt ?? pause.pausedAt).timeIntervalSince(pause.pausedAt)
            }
            return timer.startedAt.addingTimeInterval(TimeInterval(duration) + pausedDuration)
        }.max()
    }

    private func recoverInterruptedVoiceRecordings() {
        for entry in VoiceRecordingJournal.entries() {
            let url = URL(fileURLWithPath: entry.filePath)
            guard FileManager.default.fileExists(atPath: url.path) else {
                VoiceRecordingJournal.remove(recordingID: entry.recordingID)
                continue
            }
            do {
                try mediaStore.saveAudio(
                    experimentID: entry.experimentID,
                    id: entry.recordingID,
                    recordedAt: entry.startedAt,
                    sourceURL: url,
                    transcript: "",
                    note: "중단된 녹음을 복구했어요."
                )
                VoiceRecordingJournal.remove(recordingID: entry.recordingID)
            } catch ExperimentStore.StoreError.experimentNotFound {
                VoiceRecordingJournal.remove(recordingID: entry.recordingID)
                try? FileManager.default.removeItem(at: url)
            } catch {
                continue
            }
        }
        VoiceRecordingJournal.sweepUntrackedFiles()
    }
}
