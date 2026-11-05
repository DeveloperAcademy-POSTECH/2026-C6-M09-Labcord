import ComposableArchitecture
import Foundation
import LabcordiOS
import LabcordShared

extension ExperimentSessionFeature {
    func handleWatchRecord(
        _ command: WatchExperimentCommand, state: inout State
    ) -> Effect<Action> {
        guard command.experimentID == state.experimentID,
              state.watchCommand == nil,
              !state.isCompleting, !state.isReturningHome else {
            return recordFailure(command, error: .phoneBusy)
        }
        if let pending = state.watchMediaCommand {
            guard pending.operation == .takePhoto, command.operation == .cancelRecord,
                  let experimentID = command.experimentID,
                  pending.experimentID == experimentID,
                  let targetID = command.targetID, pending.targetID == targetID,
                  pending.requestID != command.requestID, state.voice.phase == .hidden else {
                return recordFailure(command, error: .phoneBusy)
            }
            return .send(.capture(.watchCommand(command)))
        }
        state.watchMediaCommand = command
        switch command.operation {
        case .startTimer, .pauseTimer, .resumeTimer, .deleteTimer:
            return .send(.timer(.watchCommand(command)))
        case .takePhoto, .startVideo, .stopVideo, .confirmRecord, .cancelRecord:
            guard state.voice.phase == .hidden else {
                state.watchMediaCommand = nil
                return recordFailure(command, error: .phoneBusy)
            }
            return .send(.capture(.watchCommand(command)))
        default:
            state.watchMediaCommand = nil
            return recordFailure(command, error: .invalidPayload)
        }
    }

    func recordFailure(
        _ command: WatchExperimentCommand, error: WatchExperimentError
    ) -> Effect<Action> {
        .send(.watchRecordResponse(WatchExperimentResponse(
            requestID: command.requestID, phase: .failed, error: error
        )))
    }

    private func failWatchDrain(state: inout State) -> Effect<Action> {
        guard state.watchCommand != nil, !state.watchClosingResources else { return .none }
        state.timer.isClosing = false
        return .merge(
            .send(.timer(.timerTick(now))),
            finishWatchClose(state: &state, error: .storageFailed)
        )
    }

    var watchCompletionReducer: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .timer(.delegate(response)),
                 let .capture(.delegate(.watchResponse(response))):
                return .send(.watchRecordResponse(response))
            case let .watchRecordResponse(response):
                if state.watchMediaCommand?.requestID == response.requestID,
                   response.phase == .failed || response.phase == .completed
                    || response.record != nil {
                    state.watchMediaCommand = nil
                }
                return .none
            case let .voice(.stopped(id, recording)):
                guard state.watchCommand != nil,
                      id == state.voice.sessionID else { return .none }
                guard recording != nil || state.voice.errorMessage == nil else {
                    return failWatchDrain(state: &state)
                }
                return .send(.watchDrainProgress)
            case let .voice(.event(id, event)):
                guard state.watchCommand != nil,
                      id == state.voice.sessionID else { return .none }
                if case .failed = event { return failWatchDrain(state: &state) }
                return .send(.watchDrainProgress)
            case .voice(.saved),
                 .capture(.photo(.saved)), .capture(.photo(.captured)),
                 .capture(.video(.saved)), .capture(.video(.recorded)), .timer(.timerSaved):
                guard state.watchCommand != nil else { return .none }
                return .send(.watchDrainProgress)
            case let .voice(.saveFailed(id, _)):
                guard id == state.voice.recordID else { return .none }
                return failWatchDrain(state: &state)
            case let .voice(.startFailed(id, _)),
                 let .voice(.startPermissionFailed(id, _)):
                guard id == state.voice.sessionID else { return .none }
                return failWatchDrain(state: &state)
            case let .capture(.photo(.saveFailed(id, _))):
                guard id == state.capture.photo.recordID else { return .none }
                return failWatchDrain(state: &state)
            case let .capture(.video(.saveFailed(id, _))):
                guard id == state.capture.video.recordID else { return .none }
                return failWatchDrain(state: &state)
            case let .capture(.video(.recordingFailed(id, _))):
                guard id == state.capture.video.sessionID else { return .none }
                return failWatchDrain(state: &state)
            case .capture(.photo(.captureFailed)), .timer(.timerSaveFailed):
                return failWatchDrain(state: &state)
            default:
                return .none
            }
        }
    }
}
