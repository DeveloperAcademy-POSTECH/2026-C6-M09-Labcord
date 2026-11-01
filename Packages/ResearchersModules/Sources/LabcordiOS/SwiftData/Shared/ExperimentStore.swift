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
            storage = try ModelContainer(
                for: Experiment.self, ExperimentRecord.self, Pause.self, ExperimentStatusEntry.self
            )
            container = storage
        }
        let context = ModelContext(storage)
        context.autosaveEnabled = false
        return context
    }
}
