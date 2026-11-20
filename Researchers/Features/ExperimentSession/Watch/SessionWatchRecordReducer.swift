import ComposableArchitecture
import Foundation
import LabcordiOS
import LabcordShared
import OSLog

private let remoteCaptureLog = Logger(subsystem: "Labcord", category: "Capture")

extension ExperimentSessionFeature {
    var watchRecordReducer: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .watchRecordControl(command):
                if command.isCameraCommand,
                   !PhoneWatchExperimentCoordinator.shared.isAwaitingCameraCommand(
                    command.requestID
                   ) { return .none }
                guard command.experimentID == state.experimentID, state.watchCommand == nil,
                      !state.isPausePresented,
                      !state.isReturningHome else {
                    return .send(.watchRecordResponse(.init(
                        requestID: command.requestID, phase: .failed, error: .phoneBusy
                    )))
                }
                if let pending = state.watchMediaCommand {
                    guard command.canInterruptCameraCommand(pending),
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
                    let startsCapture = command.operation == .takePhoto
                        || command.operation == .startVideo
                    if startsCapture, let blocker = captureStartBlocker(state) {
                        remoteCaptureLog.notice("""
                            Watch capture blocked id=\(command.requestID, privacy: .public) \
                            reason=\(blocker, privacy: .public)
                            """)
                        state.watchMediaCommand = nil
                        return .send(.watchRecordResponse(.init(
                            requestID: command.requestID, phase: .failed, error: .phoneBusy
                        )))
                    }
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
            case let .capture(.watchCommandExpired(requestID)):
                if state.watchMediaCommand?.requestID == requestID {
                    state.watchMediaCommand = nil
                }
                return .none
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

    func captureStartBlocker(_ state: State) -> String? {
        if state.isPausePresented { return "paused" }
        if state.isReturningHome || state.watchCommand != nil { return "sessionCommand" }
        if state.isRemotePreview { return "remotePreview" }
        if state.voice.phase != .hidden { return "phoneVoice" }
        if PhoneWatchAudioService.shared.isCapturing(in: state.experimentID, at: now) {
            return "watchVoiceCapturing"
        }
        return nil
    }
}
