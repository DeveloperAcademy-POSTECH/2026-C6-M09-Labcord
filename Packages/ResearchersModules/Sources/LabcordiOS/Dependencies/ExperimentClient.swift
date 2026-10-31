import ComposableArchitecture
import Foundation
import LabcordShared

public struct ExperimentClient: Sendable {
    public var load: @MainActor @Sendable () throws -> [ExperimentListEntry]
    public var loadDetail: @MainActor @Sendable (UUID) throws -> ExperimentSessionDetail?
    public var loadResultDetail: @MainActor @Sendable (UUID) throws -> ExperimentResultDetail?
    public var create: @MainActor @Sendable (UUID, Date) throws -> ExperimentListEntry
    public var leaveSession: @MainActor @Sendable (UUID, UUID, Date) throws -> Void
    public var saveTimer: @MainActor @Sendable (UUID, ExperimentTimer, Date?) throws -> Void
    public var complete: @MainActor @Sendable (UUID, Date) throws -> Void
    public var delete: @MainActor @Sendable (UUID) throws -> Void

    public init(
        load: @escaping @MainActor @Sendable () throws -> [ExperimentListEntry],
        loadDetail: @escaping @MainActor @Sendable (UUID) throws -> ExperimentSessionDetail?,
        loadResultDetail: @escaping @MainActor @Sendable (UUID) throws -> ExperimentResultDetail?,
        create: @escaping @MainActor @Sendable (UUID, Date) throws -> ExperimentListEntry,
        leaveSession: @escaping @MainActor @Sendable (UUID, UUID, Date) throws -> Void,
        saveTimer: @escaping @MainActor @Sendable (UUID, ExperimentTimer, Date?) throws -> Void,
        complete: @escaping @MainActor @Sendable (UUID, Date) throws -> Void,
        delete: @escaping @MainActor @Sendable (UUID) throws -> Void
    ) {
        self.load = load
        self.loadDetail = loadDetail
        self.loadResultDetail = loadResultDetail
        self.create = create
        self.leaveSession = leaveSession
        self.saveTimer = saveTimer
        self.complete = complete
        self.delete = delete
    }
}

extension ExperimentClient: DependencyKey {
    public static let liveValue = ExperimentClient(
        load: { try ExperimentRepository.shared.load() },
        loadDetail: { try ExperimentRepository.shared.loadDetail(id: $0) },
        loadResultDetail: { try ExperimentRepository.shared.loadResultDetail(id: $0) },
        create: { try ExperimentRepository.shared.create(id: $0, at: $1) },
        leaveSession: {
            try ExperimentRepository.shared.leaveSession(id: $0, entryID: $1, at: $2)
        },
        saveTimer: {
            try ExperimentRepository.shared.saveTimer(experimentID: $0, timer: $1, endedAt: $2)
        },
        complete: { try ExperimentRepository.shared.complete(id: $0, at: $1) },
        delete: { try ExperimentRepository.shared.delete(id: $0) }
    )
}

extension DependencyValues {
    public var experimentClient: ExperimentClient {
        get { self[ExperimentClient.self] }
        set { self[ExperimentClient.self] = newValue }
    }
}
