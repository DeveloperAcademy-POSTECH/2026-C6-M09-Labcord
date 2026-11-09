import ComposableArchitecture
import Foundation
import LabcordiOS

extension VoiceRecordingFeature {
    func reduceWatchPause(state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case .discardForWatchPause:
            guard state.isSessionClosing, !state.isPauseCancellationPending, !state.isSaving,
                  [.starting, .recording, .stopping].contains(state.phase) else { return .none }
            let cancellationID = uuid()
            state.sessionID = cancellationID
            state.isPauseCancellationPending = true
            state.shouldSaveOnStop = false
            return .concatenate(
                .cancel(id: CancelID.voiceStream),
                .cancel(id: CancelID.voiceStop),
                .run { send in
                    await speechRecordingClient.cancel()
                    await send(.watchPauseDiscarded(cancellationID))
                }
            )
        case let .watchPauseDiscarded(id):
            guard state.sessionID == id, state.isPauseCancellationPending else { return .none }
            state.isPauseCancellationPending = false
            state.phase = .hidden
            resetReview(state: &state)
            return .none
        default:
            return .none
        }
    }

    func finishStopped(_ recording: SpeechRecording, state: inout State) -> Effect<Action> {
        if recording.captureInterrupted {
            return interrupted(
                recording, message: "녹음 저장이 중단됐어요. 보관된 원본을 확인해주세요.",
                state: &state
            )
        }
        return .merge(finishRecording(recording, state: &state), .cancel(id: CancelID.voiceStream))
    }

    func interrupted(
        _ recording: SpeechRecording, message: String, state: inout State
    ) -> Effect<Action> {
        guard state.phase == .recording || state.phase == .stopping else { return .none }
        state.shouldSaveOnStop = false
        let effect = finishRecording(recording, autoSave: false, state: &state)
        state.errorMessage = message
        return effect
    }

    func finishRecording(
        _ recording: SpeechRecording,
        autoSave: Bool = true,
        state: inout State
    ) -> Effect<Action> {
        let id = recording.recordingID
        state.recording = recording
        state.transcript = recording.transcript
        if recording.transcriptionIncomplete {
            state.errorMessage = "음성 전사를 완료하지 못했어요. 녹음 원본을 확인해주세요."
        }
        state.recordID = id
        state.recordedAt = state.recordedAt ?? now
        state.phase = .finished
        state.saveError = nil
        state.isAutoSavePending = autoSave
        guard autoSave else { return .none }
        if state.shouldSaveOnStop { return saveAudio(state: &state) }
        return .run { send in
            try await Task.sleep(for: .seconds(3))
            await send(.autoSaveElapsed(id))
        }
        .cancellable(id: CancelID.autoSave, cancelInFlight: true)
    }

    func saveAudio(state: inout State) -> Effect<Action> {
        guard state.phase == .finished,
              let id = state.recordID,
              let recordedAt = state.recordedAt,
              let recording = state.recording,
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
                    try await experimentClient.saveAudio(
                        experimentID,
                        id,
                        recordedAt,
                        recording.audioURL,
                        recording.transcript
                    )
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

    func resetReview(state: inout State) {
        state.transcript = ""
        state.recording = nil
        state.recordID = nil
        state.recordedAt = nil
        state.isSaving = false
        state.saveError = nil
        state.isAutoSavePending = false
        state.shouldSaveOnStop = false
    }
}
