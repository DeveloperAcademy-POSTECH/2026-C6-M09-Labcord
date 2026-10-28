import ComposableArchitecture
import Foundation

struct ExperimentEntryClient: Sendable {
    var load: @MainActor @Sendable () throws -> [ExperimentListEntry]
    var create: @MainActor @Sendable (UUID, Date) throws -> ExperimentListEntry
    var delete: @MainActor @Sendable (UUID) throws -> Void
}

extension ExperimentEntryClient: DependencyKey {
    static let liveValue = ExperimentEntryClient(
        load: { try ExperimentEntryRepository.shared.load() },
        create: { try ExperimentEntryRepository.shared.create(id: $0, at: $1) },
        delete: { try ExperimentEntryRepository.shared.delete(id: $0) }
    )
}

extension DependencyValues {
    var experimentEntryClient: ExperimentEntryClient {
        get { self[ExperimentEntryClient.self] }
        set { self[ExperimentEntryClient.self] = newValue }
    }
}
