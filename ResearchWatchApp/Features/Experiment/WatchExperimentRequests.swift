import ComposableArchitecture
import Foundation
import LabcordShared
import LabcordWatchOS

extension WatchExperimentFeature {
    func request(
        _ operation: WatchExperimentCommand.Operation,
        targetID: UUID? = nil,
        seconds: Int? = nil,
        token: UUID? = nil,
        state: inout State
    ) -> Effect<Action> {
        guard state.pending == nil else { return .none }
        guard state.isReachable else {
            state.message = WatchExperimentError.notReachable.watchMessage
            return .none
        }
        let command = WatchExperimentCommand(
            requestID: uuid(), operation: operation,
            experimentID: operation == .list ? nil : state.selectedID,
            expectedRevision: operation == .list ? nil : state.snapshot?.revision,
            targetID: targetID, durationSeconds: seconds, startToken: token
        )
        state.pending = PendingRequest(command: command, responseID: command.requestID)
        state.message = nil
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
        guard var pending = state.pending, state.isReachable else { return .none }
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
            guard state.pending?.responseID == id else { return .none }
            return fail(error, state: &state)
        case let .deliveryExpired(id):
            guard state.pending?.responseID == id,
                  state.pending?.phase == .delivering else { return .none }
            state.pending?.phase = .uncertain
            state.message = WatchExperimentError.deliveryTimeout.watchMessage
            return .none
        case let .pollRequest(id):
            guard state.pending?.command.requestID == id else { return .none }
            return checkStatus(state: &state)
        case .snapshotReceived, .streamEnded, .connectionChanged, .tick:
            return reduceLifecycle(state: &state, action: action)
        default:
            return .none
        }
    }

    func handleResponse(
        _ id: UUID, response: WatchExperimentResponse, state: inout State
    ) -> Effect<Action> {
        guard let pending = state.pending, pending.responseID == id,
              response.requestID == id else { return .none }
        guard response.version == WatchExperimentCommand.schemaVersion else {
            return fail(.unsupportedVersion, state: &state)
        }
        if let error = response.error { return fail(error, state: &state) }
        switch response.phase {
        case .received, .processing:
            state.pending?.phase = .processing
            state.message = nil
            return .merge(.cancel(id: CancelID.delivery), poll(pending.command.requestID))
        case .unknown:
            state.pending?.phase = .uncertain
            state.message = WatchExperimentError.resultUnknown.watchMessage
            return .cancel(id: CancelID.delivery)
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
        if let experiments = response.experiments, pending.command.operation == .list {
            state.experiments = experiments
        }
        if let snapshot = response.snapshot { accept(snapshot, state: &state) }
        state.pending = nil
        state.message = nil
        if pending.command.operation == .prepareStart {
            return handlePreparedStart(response, state: &state)
        }
        state.startToken = nil
        if pending.command.operation == .pause || pending.command.operation == .complete {
            state.message = "실험 상태가 반영됐어요. 기록 저장 결과는 별도로 확인해주세요."
        }
        let cancel: Effect<Action> = .merge(
            .cancel(id: CancelID.delivery), .cancel(id: CancelID.poll)
        )
        if response.snapshot == nil, pending.command.operation != .list,
           pending.command.operation != .snapshot {
            return .concatenate(cancel, .send(.refresh))
        }
        return cancel
    }

    func handlePreparedStart(
        _ response: WatchExperimentResponse, state: inout State
    ) -> Effect<Action> {
        guard let token = response.startToken,
              state.snapshot?.experiment.status == .ready else {
            state.message = "시작 준비를 확인하지 못했어요. 상태를 새로 확인해주세요."
            return .cancel(id: CancelID.delivery)
        }
        state.startToken = token
        state.screen = .countdown(3)
        return .merge(.cancel(id: CancelID.delivery), countdown(token: token))
    }

    func fail(
        _ error: WatchExperimentError, state: inout State, definitive: Bool = false
    ) -> Effect<Action> {
        state.message = error.watchMessage
        let uncertain = error == .deliveryTimeout || error == .notReachable
            || error == .resultUnknown
        if uncertain && !definitive {
            state.pending?.phase = .uncertain
        } else {
            state.pending = nil
            state.startToken = nil
        }
        return .merge(.cancel(id: CancelID.delivery), .cancel(id: CancelID.poll))
    }

    func poll(_ id: UUID) -> Effect<Action> {
        .run { [clock] send in
            try await clock.sleep(for: .seconds(1))
            await send(.pollRequest(id))
        }
        .cancellable(id: CancelID.poll, cancelInFlight: true)
    }
}
