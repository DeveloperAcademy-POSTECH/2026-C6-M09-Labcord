import ComposableArchitecture
import Foundation

public struct ExperimentClient: Sendable {
    public var load: @MainActor @Sendable () throws -> [ExperimentListEntry]
    public var create: @MainActor @Sendable (UUID, Date) throws -> ExperimentListEntry
    public var delete: @MainActor @Sendable (UUID) throws -> Void

    public init(
        load: @escaping @MainActor @Sendable () throws -> [ExperimentListEntry],
        create: @escaping @MainActor @Sendable (UUID, Date) throws -> ExperimentListEntry,
        delete: @escaping @MainActor @Sendable (UUID) throws -> Void
    ) {
        self.load = load
        self.create = create
        self.delete = delete
    }
}

extension ExperimentClient: DependencyKey {
    public static let liveValue = ExperimentClient(
        load: { try ExperimentRepository.shared.load() },
        create: { try ExperimentRepository.shared.create(id: $0, at: $1) },
        delete: { try ExperimentRepository.shared.delete(id: $0) }
    )
}

extension DependencyValues {
    public var experimentClient: ExperimentClient {
        get { self[ExperimentClient.self] }
        set { self[ExperimentClient.self] = newValue }
    }
}
