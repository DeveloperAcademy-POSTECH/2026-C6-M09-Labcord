import ComposableArchitecture
import Foundation
import LabcordShared
import LabcordWatchOS

extension WatchExperimentFeature {
    func close(state: inout State) -> Effect<Action> {
        let cancellingPreparation = state.pending?.command.operation == .prepareStart
        if cancellingPreparation { state.pending = nil }
        state.isRequestingPermission = false
        state.cleanupRequestID = nil
        state.startToken = nil
        state.countdownID = nil
        state.authorization = nil
        state.screen = state.selectedID == nil ? .selection : .experiment
        state.clearMessageUnlessInterruptionUnconfirmed()
        var effects: [Effect<Action>] = [
            .cancel(id: CancelID.permission), .cancel(id: CancelID.countdown)
        ]
        if cancellingPreparation {
            effects += [.cancel(id: CancelID.request), .cancel(id: CancelID.delivery),
                        .cancel(id: CancelID.poll)]
        }
        return .merge(effects)
    }

    func request(
        _ operation: WatchExperimentCommand.Operation,
        targetID: UUID? = nil,
        seconds: Int? = nil,
        token: UUID? = nil,
        state: inout State
    ) -> Effect<Action> {
        guard restorePending(state: &state), state.isVisible,
              state.streamID != nil, state.pending == nil else { return .none }
        guard state.isReachable else {
            state.message = WatchExperimentError.notReachable.watchMessage
            return .none
        }
        if token == nil, Authorization.requiresToken(operation) {
            guard let experimentID = state.selectedID else { return .none }
            state.authorization = Authorization(
                operation: operation, experimentID: experimentID, targetID: targetID,
                seconds: seconds
            )
            return request(.prepareStart, state: &state)
        }
        let command = WatchExperimentCommand(
            requestID: uuid(), operation: operation,
            experimentID: operation == .list ? nil : state.selectedID,
            expectedRevision: operation == .list ? nil : state.snapshot?.revision,
            targetID: targetID, durationSeconds: seconds, startToken: token
        )
        guard retainRequest(command, state: &state) else {
            guard let id = command.targetID else { return .none }
            let message = state.message ?? WatchExperimentError.storageFailed.watchMessage
            let action: WatchRecordFeature.Action = [.takePhoto, .startVideo].contains(operation)
                ? .captureRejected(id, message) : .commandFailed(id, message)
            return .send(.recording(action))
        }
        if operation == .complete { state.cleanupRequestID = command.requestID }
        state.pending = PendingRequest(command: command, responseID: command.requestID)
        state.clearMessageUnlessInterruptionUnconfirmed()
        return .merge(send(command), scheduleDeliveryTimeout(for: command.requestID))
    }

    func send(_ command: WatchExperimentCommand) -> Effect<Action> {
        .run { [client] send in
            do {
                let response = try await client.send(command)
                try Task.checkCancellation()
                await send(.response(command.requestID, response))
            } catch is CancellationError {
                return
            } catch let error as WatchExperimentError {
                await send(.requestFailed(command.requestID, error))
            } catch {
                await send(.requestFailed(command.requestID, .resultUnknown))
            }
        }
        .cancellable(id: CancelID.request, cancelInFlight: true)
    }

    func scheduleDeliveryTimeout(for id: UUID) -> Effect<Action> {
        .run { [clock] send in
            try await clock.sleep(for: .seconds(3))
            await send(.deliveryExpired(id))
        }
        .cancellable(id: CancelID.delivery, cancelInFlight: true)
    }

    func checkStatus(state: inout State) -> Effect<Action> {
        guard state.isVisible, state.streamID != nil, var pending = state.pending,
              state.isReachable else { return .none }
        let command = WatchExperimentCommand(
            requestID: uuid(), operation: .requestStatus,
            experimentID: pending.command.experimentID, targetID: pending.command.requestID
        )
        pending.responseID = command.requestID
        pending.phase = .delivering
        state.pending = pending
        return .merge(send(command), scheduleDeliveryTimeout(for: command.requestID))
    }

    func reduceResponse(state: inout State, action: Action) -> Effect<Action> {
        switch action {
        case let .response(id, response):
            return handleResponse(id, response: response, state: &state)
        case let .requestFailed(id, error):
            return handleRequestFailure(id, error: error, state: &state)
        case let .deliveryExpired(id):
            guard state.pending?.responseID == id,
                  state.pending?.phase == .delivering else { return .none }
            state.pending?.phase = .uncertain
            state.canRetryPendingCancellation = false
            state.message = WatchExperimentError.deliveryTimeout.watchMessage
            if let pending = state.pending,
               WatchRequestPolicy.canAbandon(pending.command.operation) {
                return .merge(
                    fail(.deliveryTimeout, state: &state), .cancel(id: CancelID.request)
                )
            }
            return .none
        case let .pollRequest(id):
            guard state.pending?.command.requestID == id else { return .none }
            return checkStatus(state: &state)
        case .snapshotReceived, .streamEnded, .connectionChanged, .connectionStatusChanged,
             .retryConnection, .tick:
            return reduceLifecycle(state: &state, action: action)
        default:
            return .none
        }
    }

    private func handleRequestFailure(
        _ id: UUID, error: WatchExperimentError, state: inout State
    ) -> Effect<Action> {
        guard let pending = state.pending, pending.responseID == id else { return .none }
        if !WatchRequestPolicy.canAbandon(pending.command.operation) {
            state.pending?.phase = .uncertain
            state.canRetryPendingCancellation = pending.command.operation == .cancelRecord
                && error == .notReachable
            state.message = error.watchMessage
            return .merge(.cancel(id: CancelID.delivery), .cancel(id: CancelID.poll))
        }
        return fail(error, state: &state)
    }

    func handleResponse(
        _ id: UUID, response: WatchExperimentResponse, state: inout State
    ) -> Effect<Action> {
        guard let pending = state.pending, pending.responseID == id,
              response.requestID == id else { return .none }
        if let rejected = rejectUnverifiedResponse(response, pending: pending, state: &state) {
            return rejected
        }
        if response.phase == .unknown, pending.command.operation == .cancelRecord {
            state.canRetryPendingCancellation = true
        }
        if let error = response.error {
            return fail(error, state: &state, definitive: response.phase == .failed)
        }
        switch response.phase {
        case .received, .processing:
            state.pending?.phase = .processing
            if response.phase == .processing, pending.command.operation == .complete,
               state.cleanupRequestID == pending.command.requestID {
                state.screen = .recordCleanup
            }
            state.clearMessageUnlessInterruptionUnconfirmed()
            return .merge(.cancel(id: CancelID.delivery), poll(pending.command.requestID))
        case .unknown:
            state.canRetryPendingCancellation = pending.command.operation == .cancelRecord
            return fail(.resultUnknown, state: &state)
        case .failed:
            return fail(.resultUnknown, state: &state, definitive: true)
        case .completed:
            return handleCompletion(response, pending: pending, state: &state)
        }
    }

    func handleCompletion(
        _ response: WatchExperimentResponse, pending: PendingRequest, state: inout State
    ) -> Effect<Action> {
        guard response.snapshot == nil
                || response.snapshot?.experiment.id == pending.command.experimentID else {
            return fail(.invalidPayload, state: &state)
        }
        guard validCompletion(response, operation: pending.command.operation) else {
            return fail(.invalidPayload, state: &state)
        }
        guard clearRetainedRequest(pending.command, state: &state) else {
            return .merge(.cancel(id: CancelID.delivery), .cancel(id: CancelID.poll))
        }
        if WatchRequestPolicy.isReadOnly(pending.command.operation) {
            state.lastReadRequestID = pending.command.requestID
        }
        if let experiments = response.experiments, pending.command.operation == .list {
            state.experiments = experiments
        }
        if let snapshot = response.snapshot { accept(snapshot, state: &state) }
        state.pending = nil
        state.canRetryPendingCancellation = false
        state.clearMessageUnlessInterruptionUnconfirmed()
        applyDeferredPhoneSession(after: pending.command.operation, state: &state)
        if pending.command.operation == .prepareStart {
            return handlePreparedStart(response, state: &state)
        }
        state.startToken = nil
        if pending.command.operation == .complete,
           state.cleanupRequestID == pending.command.requestID {
            state.screen = .recordCleanup
        }
        if pending.command.operation == .pause || pending.command.operation == .complete {
            state.message = "실험 상태가 반영됐어요. 기록 저장 결과는 별도로 확인해주세요."
        }
        let cancel: Effect<Action> = .merge(
            .cancel(id: CancelID.delivery), .cancel(id: CancelID.poll),
            recordCommandProcessed(pending.command, state: state)
        )
        if pending.command.operation != .list, pending.command.operation != .snapshot {
            return .concatenate(cancel, .send(.refresh))
        }
        return cancel
    }

    private func applyDeferredPhoneSession(
        after operation: WatchExperimentCommand.Operation, state: inout State
    ) {
        guard operation == .list, let snapshot = state.deferredPhoneSession else { return }
        state.deferredPhoneSession = nil
        followPhoneSessionIfSafe(snapshot, state: &state)
        accept(snapshot, state: &state)
    }

    private func validCompletion(
        _ response: WatchExperimentResponse, operation: WatchExperimentCommand.Operation
    ) -> Bool {
        switch operation {
        case .list: response.experiments != nil
        case .snapshot: response.snapshot != nil
        case .prepareStart: response.startToken != nil
        default: true
        }
    }

    private func recordCommandProcessed(
        _ command: WatchExperimentCommand, state: State
    ) -> Effect<Action> {
        guard let id = command.targetID,
              state.recording.records[id]?.experimentID == command.experimentID else {
            return .none
        }
        return .send(.recording(.commandProcessed(id, command.operation)))
    }

    func fail(
        _ error: WatchExperimentError, state: inout State, definitive: Bool = false
    ) -> Effect<Action> {
        if state.pending?.command.operation == .list { state.deferredPhoneSession = nil }
        state.message = error.watchMessage
        let command = state.pending?.command
        let authorization = state.authorization
        state.authorization = nil
        let uncertain = error == .deliveryTimeout || error == .notReachable
            || error == .resultUnknown || error == .invalidPayload
        let readOnly = command.map { WatchRequestPolicy.canAbandon($0.operation) } ?? false
        if !uncertain || definitive, let command,
           [.confirmRecord, .cancelRecord].contains(command.operation), let id = command.targetID {
            do { try pendingJournal.markDecisionFailed(id) } catch {
                state.pending?.phase = .uncertain
                state.message = "저장·취소 의도를 보관하지 못했어요. 기존 요청은 유지해요."
                return .merge(.cancel(id: CancelID.delivery), .cancel(id: CancelID.poll))
            }
        }
        if !uncertain || definitive, let command, command.operation == .cancelRecord,
           let effect = recoverCaptureAfterCancellationFailure(command, state: &state) {
            return effect
        }
        if uncertain && !definitive && !readOnly {
            state.pending?.phase = .uncertain
        } else {
            if let command, !clearRetainedRequest(command, state: &state) {
                return .merge(.cancel(id: CancelID.delivery), .cancel(id: CancelID.poll))
            }
            state.pending = nil
            state.startToken = nil
        }
        if state.pending == nil { state.cleanupRequestID = nil }
        var effects: [Effect<Action>] = [
            .cancel(id: CancelID.delivery), .cancel(id: CancelID.poll)
        ]
        if state.pending == nil, let id = command?.targetID ?? authorization?.targetID,
           state.recording.records[id] != nil {
            let operation = authorization?.operation ?? command?.operation
            let captureStart = operation == .takePhoto || operation == .startVideo
            let rejectedBeforeCapture: [WatchExperimentError] = [
                .cameraUnavailable, .permissionDenied, .phoneBusy, .phoneUnlockRequired,
                .activeExperimentConflict, .staleRevision, .requestExpired
            ]
            let rejectedCapture = captureStart && rejectedBeforeCapture.contains(error)
                && (definitive || error == .cameraUnavailable || error == .permissionDenied)
            let action: WatchRecordFeature.Action = rejectedCapture
                ? .captureRejected(id, error.watchMessage) : .commandFailed(id, error.watchMessage)
            effects.append(.send(.recording(action)))
        }
        return .merge(effects)
    }

    func poll(_ id: UUID) -> Effect<Action> {
        .run { [clock] send in
            try await clock.sleep(for: .seconds(1))
            await send(.pollRequest(id))
        }
        .cancellable(id: CancelID.poll, cancelInFlight: true)
    }
}
