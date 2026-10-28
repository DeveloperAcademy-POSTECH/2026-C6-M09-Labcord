import Foundation
import LabcordShared
import SwiftData

/// iPhone 앱만 사용하는 저장 구현입니다. 작업 실패가 다른 편집 context를 되돌리지 않습니다.
@MainActor
final class ExperimentEntryRepository {
    static let shared = ExperimentEntryRepository()

    private var container: ModelContainer?

    private init() {}

    func load() throws -> [ExperimentListEntry] {
        let context = try makeContext()
        return try context.fetch(FetchDescriptor<Experiment>())
            .map(Self.entry)
    }

    func create(id: UUID, at date: Date) throws -> ExperimentListEntry {
        let context = try makeContext()
        let request = FetchDescriptor<Experiment>(predicate: #Predicate { $0.id == id })
        if let existing = try context.fetch(request).first {
            return Self.entry(existing)
        }

        let experiment = Experiment(id: id, title: "새 실험", createdAt: date)
        context.insert(experiment)
        try context.save()
        return Self.entry(experiment)
    }

    func delete(id: UUID) throws {
        let context = try makeContext()
        let request = FetchDescriptor<Experiment>(predicate: #Predicate { $0.id == id })
        guard let experiment = try context.fetch(request).first else { return }
        context.delete(experiment)
        try context.save()
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

    private static func entry(_ experiment: Experiment) -> ExperimentListEntry {
        ExperimentListEntry(
            id: experiment.id,
            title: experiment.title,
            createdAt: experiment.createdAt,
            status: .init(experiment.status)
        )
    }
}
