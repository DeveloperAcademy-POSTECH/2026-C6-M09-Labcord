import ComposableArchitecture
import Foundation
import LabcordiOS
import LabcordShared

extension ExperimentSessionFeature {
    var completionReducer: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .stopTapped:
                guard state.canCloseSession else { return .none }
                state.isCompleting = true
                state.completionFailed = false
                return finishPendingMedia(state: &state)

            case .returnHomeTapped:
                guard state.canCloseSession else { return .none }
                state.isReturningHome = true
                state.exitFailed = false
                state.exitID = state.exitID ?? uuid()
                return finishPendingMedia(state: &state)

            case .continueCompletion:
                return completeWhenMediaSaved(state: &state)

            case .voice(.saved), .capture(.video(.saved)), .capture(.photo(.saved)):
                return completeWhenMediaSaved(state: &state)

            case .capture(.photo(.captured)):
                guard state.isCompleting || state.isReturningHome else { return .none }
                return .send(.capture(.photo(.saveRequested)))

            case let .voice(.saveFailed(id, _)):
                guard state.isCompleting || state.isReturningHome,
                      state.voice.recordID == id else { return .none }
                return failCompletion(state: &state)

            case let .capture(.video(.saveFailed(id, _))):
                guard state.isCompleting || state.isReturningHome,
                      state.capture.video.recordID == id else { return .none }
                return failCompletion(state: &state)

            case let .capture(.photo(.saveFailed(id, _))):
                guard state.isCompleting || state.isReturningHome,
                      state.capture.photo.recordID == id else { return .none }
                return failCompletion(state: &state)

            case let .voice(.startPermissionFailed(id, kind)):
                guard state.voice.sessionID == id else { return .none }
                let completion = state.isCompleting || state.isReturningHome
                    ? failCompletion(state: &state) : .none
                return .merge(completion, .send(.permissions(.accessFailed(kind))))

            case let .voice(.startFailed(id, _)),
                 let .voice(.event(id, .failed)),
                 let .voice(.stopped(id, nil)):
                guard state.isCompleting || state.isReturningHome,
                      state.voice.sessionID == id else { return .none }
                return failCompletion(state: &state)

            case let .capture(.video(.recordingFailed(id, _))):
                guard state.isCompleting || state.isReturningHome,
                      state.capture.video.sessionID == id else {
                    return .none
                }
                return failCompletion(state: &state)

            case .capture(.photo(.captureFailed)):
                guard state.isCompleting || state.isReturningHome else { return .none }
                return failCompletion(state: &state)

            case .stopCompleted:
                guard state.isCommittingCompletion else { return .none }
                state.isCompleting = false
                state.isCommittingCompletion = false
                state.completionRequestedAt = nil
                state.voice.isFinishingSession = false
                state.capture.video.isFinishingSession = false
                return .none

            case .homeExitCompleted:
                state.isCommittingCompletion = false
                state.completionRequestedAt = nil
                state.voice.isFinishingSession = false
                state.capture.video.isFinishingSession = false
                return .none

            case .stopFailed, .homeExitFailed:
                return failCompletion(state: &state)

            case .dismissStopFailure:
                state.completionFailed = false
                return .none

            case .dismissHomeExitFailure:
                state.exitFailed = false
                return .none
            default:
                return .none
            }
        }
    }

    private func finishPendingMedia(state: inout State) -> Effect<Action> {
        state.timer.isClosing = true
        state.completionRequestedAt = now
        state.voice.isFinishingSession = true
        state.capture.video.isFinishingSession = true
        return .concatenate(
            .send(.capture(.cancelPhotoGesture)),
            .send(.voice(.finishForSessionEnd)),
            .send(.capture(.video(.finishForSessionEnd))),
            .send(.capture(.photo(.saveRequested))),
            .send(.continueCompletion)
        )
    }

    func completeWhenMediaSaved(state: inout State) -> Effect<Action> {
        guard state.isCompleting || state.isReturningHome, !state.isCommittingCompletion,
              let completedAt = state.completionRequestedAt,
              state.voice.phase == .hidden, !state.voice.isSaving,
              state.capture.video.phase == .idle, !state.capture.video.isSaving,
              !state.capture.photo.isCapturing, !state.capture.photo.isSaving,
              state.capture.photo.capturedData == nil else { return .none }
        state.isCommittingCompletion = true
        if state.isReturningHome { return saveHomeExit(state: &state, at: completedAt) }
        let experimentID = state.experimentID
        return .run { send in
            do {
                try await experimentClient.complete(experimentID, completedAt)
                await send(.stopCompleted)
            } catch {
                await send(.stopFailed)
            }
        }
    }

    func failCompletion(state: inout State) -> Effect<Action> {
        if state.isReturningHome {
            state.exitFailed = true
        } else {
            state.completionFailed = true
        }
        state.isCompleting = false
        state.isReturningHome = false
        state.isCommittingCompletion = false
        state.completionRequestedAt = nil
        state.voice.isFinishingSession = false
        state.capture.video.isFinishingSession = false
        state.timer.isClosing = false
        return .send(.timer(.timerTick(now)))
    }

}
