import ComposableArchitecture
import Foundation
import LabcordiOS
import LabcordShared

extension ExperimentSessionFeature {
    var watchDrainEventsReducer: some Reducer<State, Action> {
        Reduce { state, action in
            guard let request = state.watchCommand, let gate = state.watchDrainGate,
                  !state.watchClosingResources else { return .none }
            let signal: WatchDrainGate.Signal
            switch action {
            case let .voice(.saved(id)):
                signal = .voiceSaved(
                    session: state.voice.sessionID, record: id,
                    accepted: state.voice.lastSavedRecordID
                )
            case let .voice(.saveFailed(id, _)):
                guard state.voice.recordID == id else { return .none }
                signal = .voiceFailed(session: state.voice.sessionID)
            case let .voice(.startFailed(id, _)), let .voice(.startPermissionFailed(id, _)):
                signal = .voiceFailed(session: id)
            case let .voice(.stopped(id, recording)):
                guard gate.voiceSession == id else { return .none }
                guard let recording, !recording.captureInterrupted else {
                    return failWatchDrain(state: &state)
                }
                signal = .voiceRecorded(session: id, record: state.voice.recordID)
            case let .voice(.event(id, event)):
                guard gate.voiceSession == id else { return .none }
                switch event {
                case .interrupted, .failed: return failWatchDrain(state: &state)
                case .finished:
                    signal = .voiceRecorded(session: id, record: state.voice.recordID)
                default: return .none
                }
            case let .capture(.photo(.captured(id, _))):
                guard gate.photoRecord == id else { return .none }
                return .send(.watchDrainProgress(request.requestID))
            case let .capture(.photo(.saved(id))):
                signal = .photoSaved(id)
            case let .capture(.photo(.saveFailed(id, _))),
                 let .capture(.photo(.captureFailed(id, _))):
                signal = .photoFailed(id)
            case let .capture(.video(.recorded(id, _))):
                guard state.capture.video.sessionID == id else { return .none }
                signal = .videoRecorded(session: id, record: state.capture.video.recordID)
            case let .capture(.video(.saved(id))):
                signal = .videoSaved(session: state.capture.video.sessionID, record: id)
            case let .capture(.video(.saveFailed(id, _))):
                signal = .videoSaveFailed(session: state.capture.video.sessionID, record: id)
            case let .capture(.video(.recordingFailed(id, _))):
                signal = .videoFailed(session: id)
            default:
                return .none
            }
            switch state.watchDrainGate?.apply(signal) {
            case .ready, .waiting: return .send(.watchDrainProgress(request.requestID))
            case .failed: return failWatchDrain(state: &state)
            case .ignored, .none: return .none
            }
        }
    }
}
