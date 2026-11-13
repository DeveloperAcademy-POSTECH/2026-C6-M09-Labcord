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
        recoverInterruptedVoiceRecordings()
        let context = try store.makeContext()
        let request = FetchDescriptor<Experiment>()
        let now = Date.now
        return try context.fetch(request).map { Self.entry($0, at: now) }
    }

    private func recoverInterruptedVoiceRecordings() {
        let journal = VoiceRecordingJournal.scan()
        if journal.directoryUnavailable || journal.unreadableCount > 0 {
            SpeechDebugLog.write(
                "voice journal scan failed for \(journal.unreadableCount) entries"
            )
        }
        for entry in VoiceRecordingJournal.recoverableEntries(in: journal.entries) {
            let recordedURL = URL(fileURLWithPath: entry.filePath)
            let relocatedURL = URL.applicationSupportDirectory
                .appending(path: "IncompleteVoiceRecordings/\(entry.experimentID.uuidString)")
                .appending(path: recordedURL.lastPathComponent)
            let original = FileManager.default.fileExists(atPath: recordedURL.path)
                ? recordedURL : relocatedURL
            let recovered = VoiceRecordingRecovery.recover(original: original) { copy in
                try mediaStore.saveAudio(
                    experimentID: entry.experimentID, id: entry.recordingID,
                    recordedAt: entry.startedAt, sourceURL: copy, transcript: ""
                )
                let context = try store.makeContext()
                guard let experiment = try store.find(id: entry.experimentID, in: context),
                      let record = experiment.records.first(where: {
                          $0.id == entry.recordingID && $0.type == .audio
                      }),
                      let path = record.filePath else { return false }
                return FileManager.default.fileExists(
                    atPath: URL.applicationSupportDirectory.appending(path: path).path
                )
            }
            if recovered { VoiceRecordingJournal.remove(recordingID: entry.recordingID) }
        }
    }

    func create(id: UUID, at date: Date) throws -> ExperimentListEntry {
        let context = try store.makeContext()
        if let existing = try store.find(id: id, in: context) {
            return Self.entry(existing)
        }

        let defaults = UserDefaults.standard
        let titles = Set(try context.fetch(FetchDescriptor<Experiment>()).map(\.title))
        let nextNumber = ExperimentTitle.availableNumber(
            for: "새 실험",
            startingAt: defaults.integer(forKey: "lastExperimentNumber") + 1,
            existing: titles
        )
        let experiment = Experiment(
            id: id,
            title: ExperimentTitle.numbered("새 실험", number: nextNumber),
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
}
