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

    @ObservableState
    struct State: Equatable {
        var phase: Phase = .idle
        var sessionID = UUID()
        var errorMessage: String?
        let experimentID: UUID
        var recordID: UUID?
        var recordedAt: Date?
        var isSaving = false
        var saveError: String?
        var hasPlaybackFinished = false
        var isAutoSavePending = false
        var isFinishingSession = false
    }

    enum Action: Equatable {
        case prepareRequested
        case recordRequested
        case started(UUID, Date)
        case recorded(UUID, URL)
        case recordingFailed(UUID, String)
        case retakeRequested
        case saveRequested
        case finishForSessionEnd
        case playbackFinished(UUID)
        case autoSaveElapsed(UUID)
        case saved(UUID)
        case saveFailed(UUID, String)
        case saveErrorDismissed
        case cancelCleanupFailed(String)
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
            switch action {
            case .prepareRequested:
                return .run { _ in
                    try? await cameraSessionClient.prepareVideoRecording()
                }

            case .recordRequested:
                guard state.phase == .idle else { return .none }
                state.sessionID = UUID()
                state.phase = .starting
                let id = state.sessionID
                return .run { send in
                    do {
                        let url = try await cameraSessionClient.recordVideo {
                            Task { await send(.started(id, .now)) }
                        }
                        guard !Task.isCancelled else {
                            await cameraSessionClient.discardVideo(url)
                            return
                        }
                        await send(.recorded(id, url))
                    } catch let error as PermissionAccessError {
                        await send(.delegate(.permissionAccessFailed(error.kind)))
                        await send(.recordingFailed(id, error.localizedDescription))
                    } catch is CancellationError {
                        return
                    } catch {
                        await send(.recordingFailed(id, error.localizedDescription))
                    }
                }
                .cancellable(id: CancelID.recording, cancelInFlight: true)

            case let .started(id, startedAt):
                guard id == state.sessionID, state.phase == .starting else { return .none }
                state.phase = .recording(startedAt)
                state.recordedAt = startedAt
                guard state.isFinishingSession else { return .none }
                return .run { _ in await cameraSessionClient.stopVideoRecording() }

            case let .recorded(id, url):
                guard id == state.sessionID else {
                    return .run { _ in await cameraSessionClient.discardVideo(url) }
                }
                state.phase = .preview(url)
                state.recordID = uuid()
                state.recordedAt = state.recordedAt ?? now
                state.saveError = nil
                state.hasPlaybackFinished = false
                state.isAutoSavePending = false
                return state.isFinishingSession ? saveVideo(state: &state) : .none

            case let .recordingFailed(id, message):
                guard id == state.sessionID else { return .none }
                state.phase = .idle
                state.errorMessage = message
                return .none

            case .retakeRequested:
                guard case let .preview(url) = state.phase, !state.isSaving,
                      !state.isFinishingSession else { return .none }
                state.phase = .idle
                resetReview(state: &state)
                return .merge(
                    .cancel(id: CancelID.autoSave),
                    .run { _ in await cameraSessionClient.discardVideo(url) }
                )

            case .saveRequested:
                return saveVideo(state: &state)

            case .finishForSessionEnd:
                guard state.isFinishingSession else { return .none }
                switch state.phase {
                case .recording:
                    return .run { _ in await cameraSessionClient.stopVideoRecording() }
                case .preview: return saveVideo(state: &state)
                case .idle, .starting: return .none
                }

            case let .playbackFinished(id):
                guard state.recordID == id,
                      !state.hasPlaybackFinished,
                      !state.isSaving else { return .none }
                state.hasPlaybackFinished = true
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

            case .cancelRequested:
                guard !state.isFinishingSession else { return .none }
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
                        await cameraSessionClient.cancelVideoRecording()
                        guard let videoURL else { return }
                        if let savingRecordID {
                            do {
                                try await experimentClient.cancelVideoSave(
                                    experimentID, savingRecordID, videoURL
                                )
                            } catch {
                                await send(.cancelCleanupFailed(error.localizedDescription))
                            }
                        } else {
                            await cameraSessionClient.discardVideo(videoURL)
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

    private func saveVideo(state: inout State) -> Effect<Action> {
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

    private func resetReview(state: inout State) {
        state.recordID = nil
        state.recordedAt = nil
        state.isSaving = false
        state.saveError = nil
        state.hasPlaybackFinished = false
        state.isAutoSavePending = false
        state.isFinishingSession = false
    }
}
