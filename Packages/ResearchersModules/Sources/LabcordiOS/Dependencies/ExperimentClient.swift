import ComposableArchitecture
import Foundation
import LabcordShared

public enum RecentProtocolAccessError: Error, Sendable {
    case notConfigured
}

public struct ExperimentClient: Sendable {
    public var load: @MainActor @Sendable () throws -> [ExperimentListEntry]
    public var loadRecentProtocols: @MainActor @Sendable () throws -> [RecentProtocolEntry]
    public var loadDetail: @MainActor @Sendable (UUID) throws -> ExperimentSessionDetail?
    public var loadResultDetail: @MainActor @Sendable (UUID) throws -> ExperimentResultDetail?
    public var updateTitle: @MainActor @Sendable (UUID, String) throws -> ExperimentResultDetail
    public var updateRecordContent: @MainActor @Sendable (
        UUID, UUID, String, String?
    ) throws -> ExperimentResultDetail
    public var deleteRecord: @MainActor @Sendable (UUID, UUID) throws -> ExperimentResultDetail
    public var create: @MainActor @Sendable (UUID, Date) throws -> ExperimentListEntry
    public var leaveSession: @MainActor @Sendable (UUID, UUID, Date) throws -> Void
    public var saveTimer: @MainActor @Sendable (UUID, ExperimentTimer, Date?) throws -> Void
    public var savePhoto: @MainActor @Sendable (UUID, UUID, Date, Data) throws -> Void
    public var saveVideo: @MainActor @Sendable (UUID, UUID, Date, URL) throws -> Void
    public var saveAudio: @MainActor @Sendable (UUID, UUID, Date, URL, String) throws -> Void
    public var cancelVideoSave: @MainActor @Sendable (UUID, UUID, URL) throws -> Void
    public var cancelAudioSave: @MainActor @Sendable (UUID, UUID, URL) throws -> Void
    public var complete: @MainActor @Sendable (UUID, Date) throws -> Void
    public var delete: @MainActor @Sendable (UUID) throws -> Void

    public init(
        load: @escaping @MainActor @Sendable () throws -> [ExperimentListEntry],
        loadDetail: @escaping @MainActor @Sendable (UUID) throws -> ExperimentSessionDetail?,
        loadResultDetail: @escaping @MainActor @Sendable (UUID) throws -> ExperimentResultDetail?,
        updateTitle: @escaping @MainActor @Sendable (
            UUID, String
        ) throws -> ExperimentResultDetail,
        updateRecordContent: @escaping @MainActor @Sendable (
            UUID, UUID, String, String?
        ) throws -> ExperimentResultDetail,
        deleteRecord: @escaping @MainActor @Sendable (
            UUID, UUID
        ) throws -> ExperimentResultDetail,
        create: @escaping @MainActor @Sendable (UUID, Date) throws -> ExperimentListEntry,
        leaveSession: @escaping @MainActor @Sendable (UUID, UUID, Date) throws -> Void,
        saveTimer: @escaping @MainActor @Sendable (UUID, ExperimentTimer, Date?) throws -> Void,
        savePhoto: @escaping @MainActor @Sendable (UUID, UUID, Date, Data) throws -> Void,
        saveVideo: @escaping @MainActor @Sendable (UUID, UUID, Date, URL) throws -> Void,
        saveAudio: @escaping @MainActor @Sendable (UUID, UUID, Date, URL, String) throws -> Void,
        cancelVideoSave: @escaping @MainActor @Sendable (UUID, UUID, URL) throws -> Void,
        cancelAudioSave: @escaping @MainActor @Sendable (UUID, UUID, URL) throws -> Void,
        complete: @escaping @MainActor @Sendable (UUID, Date) throws -> Void,
        delete: @escaping @MainActor @Sendable (UUID) throws -> Void,
        loadRecentProtocols: @escaping @MainActor @Sendable () throws -> [RecentProtocolEntry] = {
            throw RecentProtocolAccessError.notConfigured
        }
    ) {
        self.load = load
        self.loadRecentProtocols = loadRecentProtocols
        self.loadDetail = loadDetail
        self.loadResultDetail = loadResultDetail
        self.updateTitle = updateTitle
        self.updateRecordContent = updateRecordContent
        self.deleteRecord = deleteRecord
        self.create = create
        self.leaveSession = leaveSession
        self.saveTimer = saveTimer
        self.savePhoto = savePhoto
        self.saveVideo = saveVideo
        self.saveAudio = saveAudio
        self.cancelVideoSave = cancelVideoSave
        self.cancelAudioSave = cancelAudioSave
        self.complete = complete
        self.delete = delete
    }
}

extension ExperimentClient: DependencyKey {
    public static let liveValue = ExperimentClient(
        load: { try ExperimentListRepository.shared.load() },
        loadDetail: {
            try ExperimentSessionRepository.shared.loadDetail(id: $0)
        },
        loadResultDetail: { try ExperimentResultRepository.shared.loadResultDetail(id: $0) },
        updateTitle: { try ExperimentResultRepository.shared.updateTitle(id: $0, title: $1) },
        updateRecordContent: {
            try ExperimentResultRepository.shared.updateRecordContent(
                experimentID: $0, recordID: $1, note: $2, transcript: $3
            )
        },
        deleteRecord: {
            try ExperimentResultRepository.shared.deleteRecord(experimentID: $0, recordID: $1)
        },
        create: { try ExperimentListRepository.shared.create(id: $0, at: $1) },
        leaveSession: {
            try ExperimentSessionRepository.shared.leaveSession(id: $0, entryID: $1, at: $2)
        },
        saveTimer: {
            try ExperimentSessionRepository.shared.saveTimer(
                experimentID: $0, timer: $1, endedAt: $2
            )
        },
        savePhoto: {
            try ExperimentSessionRepository.shared.savePhoto(
                experimentID: $0, id: $1, recordedAt: $2, data: $3
            )
        },
        saveVideo: {
            try ExperimentSessionRepository.shared.saveVideo(
                experimentID: $0, id: $1, recordedAt: $2, sourceURL: $3
            )
        },
        saveAudio: {
            try ExperimentSessionRepository.shared.saveAudio(
                experimentID: $0, id: $1, recordedAt: $2, sourceURL: $3, transcript: $4
            )
        },
        cancelVideoSave: {
            try ExperimentSessionRepository.shared.cancelVideoSave(
                experimentID: $0, id: $1, sourceURL: $2
            )
        },
        cancelAudioSave: {
            try ExperimentSessionRepository.shared.cancelAudioSave(
                experimentID: $0, id: $1, sourceURL: $2
            )
        },
        complete: { try ExperimentSessionRepository.shared.complete(id: $0, at: $1) },
        delete: { try ExperimentListRepository.shared.delete(id: $0) },
        loadRecentProtocols: { try RecentProtocolRepository.load() }
    )
}

extension DependencyValues {
    public var experimentClient: ExperimentClient {
        get { self[ExperimentClient.self] }
        set { self[ExperimentClient.self] = newValue }
    }
}
