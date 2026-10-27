import ComposableArchitecture
import Foundation

struct ExperimentEntryClient: Sendable {
    var load: @MainActor @Sendable () throws -> [ExperimentListEntry]
    var create: @MainActor @Sendable (UUID, Date) throws -> ExperimentListEntry
}

extension ExperimentEntryClient: DependencyKey {
    static let liveValue = Self(
        load: { try ExperimentEntryRepository.shared.load() },
        create: { try ExperimentEntryRepository.shared.create(id: $0, at: $1) }
    )
}

extension DependencyValues {
    var experimentEntryClient: ExperimentEntryClient {
        get { self[ExperimentEntryClient.self] }
        set { self[ExperimentEntryClient.self] = newValue }
    }
}
