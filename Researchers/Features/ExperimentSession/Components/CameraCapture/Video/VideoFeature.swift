import ComposableArchitecture
import Foundation
import LabcordiOS
import LabcordShared

@Reducer
struct VideoFeature {
    enum Phase: Equatable {
        case idle
        case starting
        case recording(Date)
        case preview(URL)
    }

    struct RecordingFailure: Equatable {
        let message: String
        let watchError: WatchExperimentError
    }

    @ObservableState
    struct State: Equatable {
        var phase: Phase = .idle
        var sessionID = UUID()
        var errorMessage: String?
        let experimentID: UUID
        var recordID: UUID?
        var recordedAt: Date?
        var isSaving = false
        var isSessionClosing = false
        var saveError: String?
        var lastSavedRecordID: UUID?
        var hasPlaybackFinished = false
        var isAutoSavePending = false
        var shouldSaveOnStop = false
        var shouldStopOnStart = false
        var requestedRecordID: UUID?
        var requiresExternalConfirmation = false
    }

    enum Action: Equatable {
        case recordRequested
        case watchRecordRequested(UUID)
        case shortcutRecordRequested(UUID)
        case watchStopRequested(UUID)
        case stopRequested
        case stopAndSaveRequested
        case started(UUID, Date)
        case recorded(UUID, URL)
        case recordingFailed(UUID, RecordingFailure)
        case watchCancelRequested(UUID)
        case retakeRequested
        case watchSaveRequested(UUID)
        case saveRequested
        case playbackFinished(UUID)
        case autoSaveElapsed(UUID)
        case saved(UUID)
        case saveFailed(UUID, String)
        case saveErrorDismissed
        case cancelCleanupFailed(String)
        case cancelCleanupFinished(UUID, confirmed: Bool)
        case cancelRequested
        case errorDismissed
        case delegate(Delegate)
    }

    enum Delegate: Equatable {
        case permissionAccessFailed(PermissionKind)
    }

    private nonisolated enum CancelID: Hashable, Sendable {
        case recording
        case autoSave
        case save
    }

    @Dependency(\.cameraSessionClient) var cameraSessionClient
    @Dependency(\.experimentClient) var experimentClient
    @Dependency(\.date.now) var now
    @Dependency(\.uuid) var uuid

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            if state.isSessionClosing, action.isBlockedDuringSessionClose { return .none }
            switch action {
            case let .watchRecordRequested(id):
                guard state.phase == .idle, state.requestedRecordID == nil else { return .none }
                state.requiresExternalConfirmation = true
                return startRecording(recordID: id, state: &state)

            case let .shortcutRecordRequested(id):
                guard state.phase == .idle, state.requestedRecordID == nil else { return .none }
                state.requestedRecordID = id
                return .send(.recordRequested)

            case .stopAndSaveRequested:
                guard state.phase != .idle else { return .none }
                state.shouldSaveOnStop = true
                if case .preview = state.phase { return saveVideo(state: &state) }
                return .send(.stopRequested)

            case let .watchStopRequested(id):
                guard state.requestedRecordID == id, state.requiresExternalConfirmation else {
                    return .none
                }
                return stopRecording(state: &state)

            case .stopRequested:
                return stopRecording(state: &state)

            case .recordRequested:
                guard state.phase == .idle else { return .none }
                return startRecording(recordID: state.requestedRecordID ?? uuid(), state: &state)

            case let .started(id, startedAt):
                guard id == state.sessionID, state.phase == .starting else { return .none }
                state.phase = .recording(startedAt)
                if state.shouldStopOnStart { return stopRecording(state: &state) }
                return .none

            case let .recorded(id, url):
                guard id == state.sessionID else {
                    return .run { _ in await cameraSessionClient.discardVideo(url) }
                }
                state.phase = .preview(url)
                state.recordID = state.requestedRecordID ?? uuid()
                state.recordedAt = now
                state.saveError = nil
                state.hasPlaybackFinished = false
                state.isAutoSavePending = false
                if state.shouldSaveOnStop { return saveVideo(state: &state) }
                return .none

            case let .recordingFailed(id, failure):
                guard id == state.sessionID else { return .none }
                state.phase = .idle
                state.errorMessage = failure.message
                resetReview(state: &state)
                return .none

            case let .watchCancelRequested(id):
                guard state.recordID == id, state.requiresExternalConfirmation else {
                    return .none
                }
                return retakeVideo(state: &state)

            case .retakeRequested:
                return retakeVideo(state: &state)

            case let .watchSaveRequested(id):
                guard state.recordID == id, state.requiresExternalConfirmation else {
                    return .none
                }
                return saveVideo(state: &state)

            case .saveRequested:
                return saveVideo(state: &state)

            case let .playbackFinished(id):
                guard state.recordID == id,
                      !state.hasPlaybackFinished,
                      !state.isSaving else { return .none }
                state.hasPlaybackFinished = true
                if state.requiresExternalConfirmation { return .none }
                state.isAutoSavePending = true
                return .run { send in
                    try await Task.sleep(for: .seconds(3))
                    await send(.autoSaveElapsed(id))
                }
                .cancellable(id: CancelID.autoSave, cancelInFlight: true)

            case let .autoSaveElapsed(id):
                guard state.recordID == id, state.isAutoSavePending else { return .none }
                return saveVideo(state: &state)

            case let .saved(id):
                guard state.recordID == id else { return .none }
                state.lastSavedRecordID = id
                state.phase = .idle
                resetReview(state: &state)
                return .none

            case let .saveFailed(id, message):
                guard state.recordID == id else { return .none }
                state.isSaving = false
                state.saveError = message
                return .none

            case .saveErrorDismissed:
                state.saveError = nil
                return .none

            case let .cancelCleanupFailed(message):
                state.errorMessage = message
                return .none

            case .cancelCleanupFinished:
                return .none

            case .cancelRequested:
                let sessionID = state.sessionID
                let cancelledRecordID = state.requestedRecordID ?? state.recordID
                let videoURL: URL?
                if case let .preview(url) = state.phase {
                    videoURL = url
                } else {
                    videoURL = nil
                }
                let savingRecordID = state.isSaving ? state.recordID : nil
                let experimentID = state.experimentID
                state.phase = .idle
                state.sessionID = UUID()
                resetReview(state: &state)
                return .concatenate(
                    .cancel(id: CancelID.recording),
                    .cancel(id: CancelID.autoSave),
                    .cancel(id: CancelID.save),
                    .run { send in
                        await cameraSessionClient.cancelVideoRecordingForSession(sessionID)
                        var confirmed = true
                        if let videoURL {
                            if let savingRecordID {
                                do {
                                    try await experimentClient.cancelVideoSave(
                                        experimentID, savingRecordID, videoURL
                                    )
                                } catch {
                                    confirmed = false
                                    await send(.cancelCleanupFailed(error.localizedDescription))
                                }
                            } else {
                                await cameraSessionClient.discardVideo(videoURL)
                            }
                        }
                        if let cancelledRecordID {
                            await send(.cancelCleanupFinished(
                                cancelledRecordID, confirmed: confirmed
                            ))
                        }
                    }
                )

            case .errorDismissed:
                state.errorMessage = nil
                return .none

            case .delegate:
                return .none
            }
        }
    }

}

private extension VideoFeature {
    func stopRecording(state: inout State) -> Effect<Action> {
        if state.phase == .starting { state.shouldStopOnStart = true }
        switch state.phase {
        case .starting, .recording:
            let id = state.sessionID
            return .run { _ in await cameraSessionClient.stopVideoRecording(id) }
        case .idle, .preview:
            return .none
        }
    }

    func startRecording(recordID: UUID, state: inout State) -> Effect<Action> {
        state.sessionID = UUID()
        state.requestedRecordID = recordID
        state.phase = .starting
        let id = state.sessionID
        return .run { send in
            do {
                let url = try await cameraSessionClient.recordVideo(id) {
                    Task { await send(.started(id, .now)) }
                }
                guard !Task.isCancelled else {
                    await cameraSessionClient.discardVideo(url)
                    return
                }
                await send(.recorded(id, url))
            } catch let error as PermissionAccessError {
                await send(.recordingFailed(id, .init(
                    message: error.localizedDescription, watchError: .permissionDenied
                )))
                await send(.delegate(.permissionAccessFailed(error.kind)))
            } catch is CancellationError {
                return
            } catch {
                await send(.recordingFailed(id, .init(
                    message: error.localizedDescription, watchError: .cameraUnavailable
                )))
            }
        }
        .cancellable(id: CancelID.recording, cancelInFlight: true)
    }

    func saveVideo(state: inout State) -> Effect<Action> {
        guard let id = state.recordID,
              let recordedAt = state.recordedAt,
              case let .preview(url) = state.phase,
              !state.isSaving else { return .none }
        state.isSaving = true
        state.isAutoSavePending = false
        state.saveError = nil
        let experimentID = state.experimentID
        return .concatenate(
            .cancel(id: CancelID.autoSave),
            .run { send in
                do {
                    try Task.checkCancellation()
                    try await experimentClient.saveVideo(experimentID, id, recordedAt, url)
                    try Task.checkCancellation()
                    await send(.saved(id))
                } catch is CancellationError {
                    return
                } catch {
                    await send(.saveFailed(id, error.localizedDescription))
                }
            }
            .cancellable(id: CancelID.save)
        )
    }

    func retakeVideo(state: inout State) -> Effect<Action> {
        guard case let .preview(url) = state.phase, !state.isSaving else { return .none }
        let discardedRecordID = state.requestedRecordID ?? state.recordID
        state.phase = .idle
        resetReview(state: &state)
        return .merge(
            .cancel(id: CancelID.autoSave),
            .run { send in
                await cameraSessionClient.discardVideo(url)
                if let discardedRecordID {
                    await send(.cancelCleanupFinished(discardedRecordID, confirmed: true))
                }
            }
        )

    }

    func resetReview(state: inout State) {
        state.recordID = nil
        state.recordedAt = nil
        state.isSaving = false
        state.saveError = nil
        state.hasPlaybackFinished = false
        state.isAutoSavePending = false
        state.shouldSaveOnStop = false
        state.shouldStopOnStart = false
        state.requestedRecordID = nil
        state.requiresExternalConfirmation = false
    }
}

private extension VideoFeature.Action {
    var isBlockedDuringSessionClose: Bool {
        switch self {
        case .recordRequested,
                 .watchRecordRequested,
                 .shortcutRecordRequested,
                 .retakeRequested,
                 .cancelRequested: true
        default: false
        }
    }
}
