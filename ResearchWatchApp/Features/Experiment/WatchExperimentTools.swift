import ComposableArchitecture
import Foundation
import LabcordShared

extension WatchExperimentFeature {
    func reduceTools(state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case .timersTapped:
            return navigateToStage(.timers, state: &state)
        case .timerEditorTapped:
            guard state.snapshot?.experiment.status == .running else { return .none }
            let seconds = state.timerHours * 3600 + state.timerMinutes * 60 + state.timerSeconds
            return navigateToStage(.timerEditor, timerDraftSeconds: seconds, state: &state)
        default:
            return reduceTimerInputs(state: &state, action: action)
        }
    }

    private func reduceTimerInputs(state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case let .timerHoursChanged(hours):
            state.timerHours = min(23, max(0, hours))
            return synchronizeTimerDraft(state: &state)
        case let .timerMinutesChanged(minutes):
            state.timerMinutes = min(59, max(0, minutes))
            return synchronizeTimerDraft(state: &state)
        case let .timerSecondsChanged(seconds):
            state.timerSeconds = min(59, max(0, seconds))
            return synchronizeTimerDraft(state: &state)
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
        state.screen = .experiment
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
        case let .remoteVoiceRequested(id, expiresAt):
            return requestRemoteVoicePermission(id, expiresAt: expiresAt, state: &state)
        case .recordReconnect:
            return reconnectRecords(state: &state)
        case let .recordUpdate(streamID, record):
            guard state.isVisible, state.streamID == streamID else { return .none }
            return receiveRecordUpdate(record, state: &state)
        case let .recording(.delegate(.command(operation, recordID, experimentID))):
            return recordCommand(
                operation, recordID: recordID, experimentID: experimentID, state: &state
            )
        case let .recording(.delegate(.local(input))):
            return performLocal(input, observationID: state.recordObservationID)
        case let .recording(.delegate(.closed(id))):
            guard state.isReachable, let record = state.recording.records[id], record.isSettled,
                  record.experimentID == state.selectedID else { return .none }
            return navigateToExperiment(state: &state)
        default:
            return reduceRecordObservation(state: &state, action: action)
        }
    }

    private func reduceRecordObservation(state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case let .recordStreamReady(id, observationID):
            guard state.isVisible, state.streamID == id,
                  state.recordObservationID == observationID else { return .none }
            state.recordObservationReady = true
            return .send(.recording(.delegate(.local(.reconcile))))
        case let .recordStreamEnded(id, observationID):
            guard state.streamID == id,
                  state.recordObservationID == observationID else { return .none }
            state.recordObservationID = nil
            state.recordObservationReady = false
            return .send(.recording(.recoveryFailed))
        case let .recordRecoveryFinished(observationID, succeeded):
            guard state.isVisible, state.streamID != nil, state.recordObservationReady,
                  let observationID, state.recordObservationID == observationID else {
                return .none
            }
            return .send(.recording(succeeded ? .integrationAvailable(true) : .recoveryFailed))
        default:
            return reduceInterruption(state: &state, action: action)
        }
    }

    private func reduceInterruption(state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case let .remoteVoicePermissionResult(id, requestID, expiresAt, granted):
            return completeRemoteVoicePermission(
                id, requestID: requestID, expiresAt: expiresAt, granted: granted, state: &state
            )
        case let .voicePermissionResult(id, requestID, granted):
            return completeVoicePermission(
                id, requestID: requestID, granted: granted, state: &state
            )
        case let .interruptionPrepared(id, attempt, operation):
            guard state.selectedID == id, state.isPreparingInterruption,
                  state.interruptionAttemptID == attempt else { return .none }
            state.isPreparingInterruption = false
            state.interruptionAttemptID = nil
            return .merge(
                .cancel(id: CancelID.interruptionTimeout), request(operation, state: &state)
            )
        case .cancelInterruptionPreparation:
            return cancelInterruptionPreparation(state: &state)
        case let .interruptionFailed(id, attempt):
            guard state.selectedID == id, state.isPreparingInterruption,
                  state.interruptionAttemptID == attempt else { return .none }
            state.isPreparingInterruption = false
            state.interruptionAttemptID = nil
            state.message = "녹음 저장을 확인하지 못했어요. 연결과 기록 상태를 확인하고 다시 시도해주세요."
            return .merge(
                .cancel(id: CancelID.interruptionTimeout), .cancel(id: CancelID.interruptionWork)
            )
        default:
            return reduceResponse(state: &state, action: action)
        }
    }

    private func completeVoicePermission(
        _ id: UUID, requestID: UUID, granted: Bool, state: inout State
    ) -> Effect<Action> {
        guard state.isRequestingPermission, state.permissionRequestID == requestID else {
            return .none
        }
        state.isRequestingPermission = false
        state.permissionRequestID = nil
        guard state.isVisible, state.streamID != nil, state.selectedID == id,
              !state.screenRecoveryNeeded, !state.phoneRecordingBlocksCapture,
              state.pending == nil, !state.isPreparingInterruption,
              state.hasRestoredPending, !state.pendingRecoveryFailed,
              state.snapshot?.experiment.status == .running else { return .none }
        guard granted else {
            state.message = "마이크 권한이 필요해요. Watch 설정에서 권한을 확인해주세요."
            return .none
        }
        return .send(.recording(.begin(.voice, id)))
    }

    private func cancelInterruptionPreparation(state: inout State) -> Effect<Action> {
        guard state.isPreparingInterruption else { return .none }
        state.isPreparingInterruption = false
        state.interruptionAttemptID = nil
        state.message = "저장 확인을 중단했어요. 원본을 유지하며 실험은 계속돼요."
        return .merge(
            .cancel(id: CancelID.interruptionTimeout), .cancel(id: CancelID.interruptionWork)
        )
    }

    private func beginRecord(
        _ kind: WatchRecordPresentation.Kind, state: inout State
    ) -> Effect<Action> {
        guard state.isVisible, state.pending == nil, !state.isPreparingInterruption,
              !state.screenRecoveryNeeded, !state.phoneRecordingBlocksCapture,
              state.hasRestoredPending, !state.pendingRecoveryFailed,
              state.snapshot?.experiment.status == .running,
              let id = state.selectedID else { return .none }
        guard kind == .voice || state.isReachable else { return .none }
        if kind == .voice {
            guard state.streamID != nil, !state.isRequestingPermission else { return .none }
            state.isRequestingPermission = true
            let requestID = uuid()
            state.permissionRequestID = requestID
            return .run { [microphonePermission] send in
                let granted = await microphonePermission.request()
                guard !Task.isCancelled else { return }
                await send(.voicePermissionResult(id, requestID, granted))
            }
            .cancellable(id: CancelID.permission, cancelInFlight: true)
        }
        return .send(.recording(.begin(kind, id)))
    }

    private func canStartRemoteVoice(_ id: UUID, expiresAt: Date, state: State) -> Bool {
        Date.now < expiresAt && state.isVisible && state.streamID != nil
            && !state.screenRecoveryNeeded && !state.phoneRecordingBlocksCapture
            && state.selectedID == id && state.pending == nil && !state.isPreparingInterruption
            && state.hasRestoredPending && !state.pendingRecoveryFailed
            && state.snapshot?.experiment.status == .running
            && (state.screen == .experiment || state.screen == .timers)
    }

    private func reconnectRecords(state: inout State) -> Effect<Action> {
        guard state.isVisible, let id = state.streamID else { return .none }
        let observationID = uuid()
        state.recordObservationID = observationID
        state.recordObservationReady = false
        state.recording.isIntegrated = false
        return observeRecords(id, observationID: observationID)
    }

    private func requestRemoteVoicePermission(
        _ id: UUID, expiresAt: Date, state: inout State
    ) -> Effect<Action> {
        guard !state.isRequestingPermission,
              canStartRemoteVoice(id, expiresAt: expiresAt, state: state) else { return .none }
        state.isRequestingPermission = true
        let requestID = uuid()
        state.permissionRequestID = requestID
        return .run { [microphonePermission] send in
            let granted = await microphonePermission.request()
            guard !Task.isCancelled else { return }
            await send(.remoteVoicePermissionResult(id, requestID, expiresAt, granted))
        }
        .cancellable(id: CancelID.permission, cancelInFlight: true)
    }

    private func completeRemoteVoicePermission(
        _ id: UUID, requestID: UUID, expiresAt: Date, granted: Bool, state: inout State
    ) -> Effect<Action> {
        guard state.isRequestingPermission, state.permissionRequestID == requestID else {
            return .none
        }
        state.isRequestingPermission = false
        state.permissionRequestID = nil
        guard canStartRemoteVoice(id, expiresAt: expiresAt, state: state) else { return .none }
        guard granted else {
            state.message = "마이크 권한이 필요해요. Watch 설정에서 권한을 확인해주세요."
            return .none
        }
        return .send(.recording(.beginRemoteVoice(id, expiresAt)))
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
            return rejectUnsentRecordCommand(recordID, state: state)
        }
        return request(operation, targetID: recordID, state: &state)
    }

    private func rejectUnsentRecordCommand(_ id: UUID, state: State) -> Effect<Action> {
        let message = "요청을 보내지 못했어요. 연결·실험·처리 중 상태를 확인해주세요. 원본은 유지해요."
        do {
            let retained = try pendingJournal.load()
            let decisions = try pendingJournal.loadDecisions()
            guard state.pending?.command.targetID != id, retained?.targetID != id,
                  !decisions.contains(where: { $0.recordID == id }) else {
                return .send(.recording(.commandFailed(id, message)))
            }
            return .send(.recording(.commandNotSent(id, message)))
        } catch {
            return .send(.recording(.commandFailed(id, message)))
        }
    }

    private func performLocal(
        _ input: WatchRecordingUIBridge.Input, observationID: UUID?
    ) -> Effect<Action> {
        guard let bridge = recordingBridge else { return .none }
        return .run { send in
            do {
                try await bridge.perform(input)
                if case .reconcile = input {
                    await send(.recordRecoveryFinished(observationID, true))
                }
            } catch {
                let id: UUID
                switch input {
                case let .startVoice(_, recordID), let .startRemoteVoice(_, recordID, _),
                     let .stopVoice(_, recordID),
                     let .retry(_, recordID): id = recordID
                case .reconcile, .stopForExperiment, .cancelActiveVoiceForPause:
                    await send(.recordRecoveryFinished(observationID, false))
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
        guard let bridge = recordingBridge else {
            state.message = "녹음 상태를 확인할 수 없어요. 다시 연결해주세요."
            return .none
        }
        let attempt = uuid()
        state.isPreparingInterruption = true
        state.interruptionAttemptID = attempt
        return .run { send in
            do {
                try await bridge.perform(.stopForExperiment(id))
                await send(.interruptionPrepared(id, attempt, operation))
            } catch {
                await send(.interruptionFailed(id, attempt))
            }
        }
        .cancellable(id: CancelID.interruptionWork, cancelInFlight: false)
    }

    func observeRecords(_ streamID: UUID, observationID: UUID) -> Effect<Action> {
        guard let bridge = recordingBridge else {
            return .send(.recordStreamEnded(streamID, observationID))
        }
        return .run { send in
            let updates = await bridge.updates()
            try Task.checkCancellation()
            await send(.recordStreamReady(streamID, observationID))
            for await record in updates {
                try Task.checkCancellation()
                await send(.recordUpdate(streamID, record))
            }
            guard !Task.isCancelled else { return }
            await send(.recordStreamEnded(streamID, observationID))
        }
        .cancellable(id: CancelID.recordStream, cancelInFlight: true)
    }
}
