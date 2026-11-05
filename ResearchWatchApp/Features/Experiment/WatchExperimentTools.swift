import ComposableArchitecture
import Foundation
import LabcordShared

extension WatchExperimentFeature {
    func reduceTools(state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case let .practiceRecord(kind):
            return practiceRecord(kind, state: &state)
        case .timersTapped:
            state.screen = .timers
            return .none
        case .timerEditorTapped:
            state.screen = .timerEditor
            return .none
        default:
            return reduceTimerInputs(state: &state, action: action)
        }
    }

    private func reduceTimerInputs(state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case let .timerHoursChanged(hours):
            state.timerHours = min(23, max(0, hours))
            return .none
        case let .timerMinutesChanged(minutes):
            state.timerMinutes = min(59, max(0, minutes))
            return .none
        case let .timerSecondsChanged(seconds):
            state.timerSeconds = min(59, max(0, seconds))
            return .none
        case .customTimerStarted:
            let seconds = state.timerHours * 3600 + state.timerMinutes * 60 + state.timerSeconds
            return startTimer(seconds, state: &state)
        case let .timerStarted(seconds):
            return startTimer(seconds, state: &state)
        case let .timerPaused(id):
            return timerCommand(.pauseTimer, id: id, state: &state)
        case let .timerResumed(id):
            return timerCommand(.resumeTimer, id: id, state: &state)
        case let .timerDeleted(id):
            return timerCommand(.deleteTimer, id: id, state: &state)
        default:
            return reduceRecording(state: &state, action: action)
        }
    }

    private func startTimer(_ seconds: Int, state: inout State) -> Effect<Action> {
        guard state.canOperate, state.snapshot?.experiment.status == .running,
              seconds > 0 else { return .none }
        state.screen = .timers
        return request(.startTimer, seconds: seconds, state: &state)
    }

    private func timerCommand(
        _ operation: WatchExperimentCommand.Operation, id: UUID, state: inout State
    ) -> Effect<Action> {
        guard state.canOperate, state.snapshot?.experiment.status == .running,
              state.snapshot?.timers.contains(where: { $0.id == id }) == true else { return .none }
        return request(operation, targetID: id, state: &state)
    }

    func reduceRecording(state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case let .recordTapped(kind):
            return beginRecord(kind, state: &state)
        case .recordReconnect:
            guard state.isVisible, let id = state.streamID else { return .none }
            return observeRecords(id)
        case let .recordStreamEnded(id):
            guard state.streamID == id else { return .none }
            return .send(.recording(.recoveryFailed))
        case let .recordUpdate(streamID, record):
            guard state.isVisible, state.streamID == streamID else { return .none }
            return receiveRecordUpdate(record, state: &state)
        case let .recording(.delegate(.command(operation, recordID, experimentID))):
            return recordCommand(
                operation, recordID: recordID, experimentID: experimentID, state: &state
            )
        case let .recording(.delegate(.local(input))):
            return performLocal(input)
        default:
            return reduceInterruption(state: &state, action: action)
        }
    }

    private func reduceInterruption(state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case let .interruptionPrepared(id, operation):
            guard state.selectedID == id, state.isPreparingInterruption else { return .none }
            state.isPreparingInterruption = false
            return request(operation, state: &state)
        case let .interruptionFailed(id):
            guard state.selectedID == id else { return .none }
            state.isPreparingInterruption = false
            state.message = "녹음 중단·보관을 확인하지 못했어요. 원본을 유지하고 다시 확인해주세요."
            return .none
        default:
            return reduceResponse(state: &state, action: action)
        }
    }

    private func beginRecord(
        _ kind: WatchRecordPresentation.Kind, state: inout State
    ) -> Effect<Action> {
        guard state.isVisible, state.pending == nil, !state.isPreparingInterruption,
              !state.pendingRecoveryFailed,
              state.snapshot?.experiment.status == .running,
              let id = state.selectedID else { return .none }
        guard kind == .voice || state.isReachable else { return .none }
        return .send(.recording(.begin(kind, id)))
    }

    private func recordCommand(
        _ operation: WatchExperimentCommand.Operation, recordID: UUID,
        experimentID: UUID, state: inout State
    ) -> Effect<Action> {
        if operation == .cancelRecord,
           let effect = cancelPendingPhoto(recordID, experimentID: experimentID, state: &state) {
            return effect
        }
        guard state.selectedID == experimentID, state.canOperate else {
            return .send(.recording(.commandFailed(
                recordID, "요청할 수 없어요. 연결·실험·처리 중 상태를 확인해주세요. 원본은 유지해요."
            )))
        }
        return request(operation, targetID: recordID, state: &state)
    }

    private func performLocal(_ input: WatchRecordingUIBridge.Input) -> Effect<Action> {
        guard let bridge = recordingBridge else { return .none }
        return .run { send in
            do {
                try await bridge.perform(input)
            } catch {
                let id: UUID
                switch input {
                case let .startVoice(_, recordID), let .stopVoice(_, recordID),
                     let .retry(_, recordID): id = recordID
                case .reconcile, .stopForExperiment:
                    await send(.recording(.recoveryFailed))
                    return
                }
                await send(.recording(.commandFailed(
                    id, "녹음·복구를 완료하지 못했어요. 확보한 원본을 유지하고 다시 시도해주세요."
                )))
            }
        }
    }

    func prepareInterruption(
        _ operation: WatchExperimentCommand.Operation, state: inout State
    ) -> Effect<Action> {
        guard state.canOperate, let id = state.selectedID else { return .none }
        guard let bridge = recordingBridge else { return request(operation, state: &state) }
        state.isPreparingInterruption = true
        return .run { send in
            do {
                try await bridge.perform(.stopForExperiment(id))
                await send(.interruptionPrepared(id, operation))
            } catch {
                await send(.interruptionFailed(id))
            }
        }
    }

    func observeRecords(_ streamID: UUID) -> Effect<Action> {
        guard let bridge = recordingBridge else {
            return .send(.recording(.integrationAvailable(false)))
        }
        return .merge(
            .send(.recording(.integrationAvailable(true))),
            .run { send in
                let updates = await bridge.updates()
                for await record in updates {
                    try Task.checkCancellation()
                    await send(.recordUpdate(streamID, record))
                }
                guard !Task.isCancelled else { return }
                await send(.recordStreamEnded(streamID))
            }
            .cancellable(id: CancelID.recordStream, cancelInFlight: true),
            .send(.recording(.delegate(.local(.reconcile))))
        )
    }
}
