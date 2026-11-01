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
        var request = FetchDescriptor<Experiment>()
        request.propertiesToFetch = [\.id, \.title, \.createdAt, \.status]
        return try context.fetch(request).map(Self.entry)
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
            startedAt: .now,
            mode: .free,
        )

        context.insert(experiment)
        try context.save()

        defaults.set(nextNumber, forKey: "lastExperimentNumber")
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

    private static func entry(_ experiment: Experiment) -> ExperimentListEntry {
        ExperimentListEntry(
            id: experiment.id,
            title: experiment.title,
            createdAt: experiment.createdAt,
            status: .init(experiment.status)
        )
    }
}
