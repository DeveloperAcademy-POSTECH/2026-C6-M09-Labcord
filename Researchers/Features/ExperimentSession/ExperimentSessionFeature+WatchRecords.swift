import ComposableArchitecture
import Foundation
import LabcordShared

extension ExperimentSessionFeature {
    var watchRecordReducer: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .watchRecordControl(command):
                guard command.experimentID == state.experimentID, state.watchCommand == nil,
                      !state.isPausePresented,
                      !state.isReturningHome else {
                    return .send(.watchRecordResponse(.init(
                        requestID: command.requestID, phase: .failed, error: .phoneBusy
                    )))
                }
                if let pending = state.watchMediaCommand {
                    guard pending.operation == .takePhoto, command.operation == .cancelRecord,
                          let targetID = command.targetID, pending.targetID == targetID,
                          pending.requestID != command.requestID,
                          state.voice.phase == .hidden else {
                        return .send(.watchRecordResponse(.init(
                            requestID: command.requestID, phase: .failed, error: .phoneBusy
                        )))
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
                        return .send(.watchRecordResponse(.init(
                            requestID: command.requestID, phase: .failed, error: .phoneBusy
                        )))
                    }
                    return .send(.capture(.watchCommand(command)))
                default:
                    state.watchMediaCommand = nil
                    return .send(.watchRecordResponse(.init(
                        requestID: command.requestID, phase: .failed, error: .invalidPayload
                    )))
                }
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
            default:
                return .none
            }
        }
    }
}
