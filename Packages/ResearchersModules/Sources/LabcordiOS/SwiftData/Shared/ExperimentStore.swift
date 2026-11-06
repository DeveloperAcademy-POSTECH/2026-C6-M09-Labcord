import Foundation
import LabcordShared
import SwiftData

@MainActor
final class ExperimentStore {
    enum StoreError: Error {
        case experimentNotFound
    }

    static let shared = ExperimentStore()

    private var container: ModelContainer?

    private init() {}

    func find(id: UUID, in context: ModelContext) throws -> Experiment? {
        var request = FetchDescriptor<Experiment>(predicate: #Predicate { $0.id == id })
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    func makeContext() throws -> ModelContext {
        let storage: ModelContainer
        if let container {
            storage = container
        } else {
            storage = try openContainer()
            container = storage
        }
        let context = ModelContext(storage)
        context.autosaveEnabled = false
        return context
    }

    private func openContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: ExperimentSchemaV1.self)
        do {
            return try ModelContainer(
                for: schema, migrationPlan: ExperimentMigrationPlan.self
            )
        } catch {
            // 기존 저장소와 스키마 식별자가 다르면 비우지 않고 지금 쓰던 방식으로 연다.
            return try ModelContainer(
                for: Experiment.self, ExperimentRecord.self, Pause.self,
                ExperimentStatusEntry.self
            )
        }
    }
}
