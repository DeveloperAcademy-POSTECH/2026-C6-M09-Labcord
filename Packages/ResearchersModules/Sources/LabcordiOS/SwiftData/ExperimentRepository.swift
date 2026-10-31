import Foundation
import LabcordShared
import SwiftData

@MainActor
final class ExperimentRepository {
    private enum RepositoryError: Error {
        case experimentNotFound
    }

    static let shared = ExperimentRepository()

    private var container: ModelContainer?

    private init() {}

    func load() throws -> [ExperimentListEntry] {
        let context = try makeContext()
        return try context.fetch(FetchDescriptor<Experiment>())
            .map(Self.entry)
    }

    func loadDetail(id: UUID) throws -> ExperimentSessionDetail? {
        let context = try makeContext()
        guard let experiment = try find(id: id, in: context) else { return nil }

        let timerSeconds = experiment.mode == .procedure
            ? experiment.procedure?.timerSeconds ?? []
            : []
        let timers = activeTimers(in: experiment, at: .now)
        try context.save()
        return ExperimentSessionDetail(
            title: experiment.title,
            timerSeconds: timerSeconds,
            mode: experiment.mode,
            timers: timers
        )
    }

    func loadResultDetail(id: UUID) throws -> ExperimentResultDetail? {
        let context = try makeContext()
        guard let experiment = try find(id: id, in: context) else { return nil }
        return Self.resultDetail(experiment)
    }

    func create(id: UUID, at date: Date) throws -> ExperimentListEntry {
        let context = try makeContext()
        if let existing = try find(id: id, in: context) {
            return Self.entry(existing)
        }
        
        let defaults = UserDefaults.standard
        let nextNumber = defaults.integer(forKey: "lastExperimentNumber") + 1
        let experiment = Experiment(
            id: id,
            title: "새 실험 (\(nextNumber))",
            createdAt: date,
            startedAt: .now,
            mode: .free,
        )
        
        context.insert(experiment)
        try context.save()
        
        defaults.set(nextNumber, forKey: "lastExperimentNumber")
        return Self.entry(experiment)
    }

    func leaveSession(id: UUID, entryID: UUID, at date: Date) throws {
        let context = try makeContext()
        guard let experiment = try find(id: id, in: context) else {
            throw RepositoryError.experimentNotFound
        }
        let hasRunningTimers = activeTimers(in: experiment, at: date)
            .contains { $0.status == .running }
        experiment.recordExit(
            status: hasRunningTimers ? .inProgress : .paused,
            at: date,
            entryID: entryID
        )
        try context.save()
    }

    func saveTimer(experimentID: UUID, timer: ExperimentTimer, endedAt: Date? = nil) throws {
        let context = try makeContext()
        guard let experiment = try find(id: experimentID, in: context) else {
            throw RepositoryError.experimentNotFound
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

    func complete(id: UUID, at date: Date) throws {
        let context = try makeContext()
        guard let experiment = try find(id: id, in: context) else {
            throw RepositoryError.experimentNotFound
        }
        _ = activeTimers(in: experiment, at: date)
        for record in experiment.records
            where record.type == .timer && record.timerEndedAt == nil {
            record.timerEndedAt = date
        }
        experiment.complete(at: date)
        try context.save()
    }

    func delete(id: UUID) throws {
        let context = try makeContext()
        guard let experiment = try find(id: id, in: context) else { return }
        context.delete(experiment)
        try context.save()
    }

    private func find(id: UUID, in context: ModelContext) throws -> Experiment? {
        var request = FetchDescriptor<Experiment>(predicate: #Predicate { $0.id == id })
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private func makeContext() throws -> ModelContext {
        let storage: ModelContainer
        if let container {
            storage = container
        } else {
            storage = try ModelContainer(
                for: Experiment.self, ExperimentRecord.self, Pause.self, ExperimentStatusEntry.self
            )
            container = storage
        }
        let context = ModelContext(storage)
        context.autosaveEnabled = false
        return context
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
            records: experiment.records.map { record in
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
            },
            statusHistory: experiment.statusHistory.sorted { $0.date < $1.date }.map {
                ExperimentResultDetail.StatusEntry(
                    id: $0.id,
                    status: $0.status,
                    date: $0.date
                )
            }
        )
    }

    private static func entry(_ experiment: Experiment) -> ExperimentListEntry {
        ExperimentListEntry(
            id: experiment.id,
            title: experiment.title,
            createdAt: experiment.createdAt,
            status: .init(experiment.status)
        )
    }
}
