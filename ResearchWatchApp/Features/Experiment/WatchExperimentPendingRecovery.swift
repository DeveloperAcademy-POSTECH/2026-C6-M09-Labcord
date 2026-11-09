import ComposableArchitecture
import Foundation
import LabcordShared

extension WatchExperimentFeature {
    func suspendPendingRequest(state: inout State) {
        guard let pending = state.pending else { return }
        if WatchRequestPolicy.canAbandon(pending.command.operation) {
            state.pending = nil
        } else {
            state.pending?.phase = .uncertain
        }
    }

    func restorePending(state: inout State) -> Bool {
        guard !state.hasRestoredPending else { return true }
        do {
            if let command = try pendingJournal.load() {
                state.selectedID = command.experimentID
                state.screen = .experiment
                state.pending = PendingRequest(
                    command: command, responseID: command.requestID, phase: .uncertain
                )
                state.message = "이전 요청의 결과를 먼저 확인하고 있어요. 확인 전에는 새 명령을 실행하지 않아요."
            }
            state.pendingRecoveryFailed = false
            state.hasRestoredPending = true
            return true
        } catch {
            state.pendingRecoveryFailed = true
            state.message = "보관된 요청을 읽지 못했어요. 기존 요청을 유지하고 다시 확인해주세요."
            return false
        }
    }

    func retainRequest(_ command: WatchExperimentCommand, state: inout State) -> Bool {
        guard !WatchRequestPolicy.canAbandon(command.operation) else { return true }
        do {
            try pendingJournal.save(command)
            return true
        } catch {
            state.message = "요청을 보관하지 못해 전송하지 않았어요. 저장 공간을 확인해주세요."
            return false
        }
    }

    func clearRetainedRequest(_ command: WatchExperimentCommand, state: inout State) -> Bool {
        guard !WatchRequestPolicy.canAbandon(command.operation) else { return true }
        do {
            try pendingJournal.clear(command.requestID)
            return true
        } catch {
            state.pending?.phase = .uncertain
            state.message = "요청 결과의 보관 상태를 정리하지 못했어요. 같은 요청 상태를 다시 확인해주세요."
            return false
        }
    }
    func rejectUnverifiedResponse(
        _ response: WatchExperimentResponse, pending: PendingRequest, state: inout State
    ) -> Effect<Action>? {
        guard response.version == WatchExperimentCommand.schemaVersion else {
            if !WatchRequestPolicy.canAbandon(pending.command.operation) {
                state.pending?.phase = .uncertain
                state.message = WatchExperimentError.unsupportedVersion.watchMessage
                return .merge(.cancel(id: CancelID.delivery), .cancel(id: CancelID.poll))
            }
            return fail(.unsupportedVersion, state: &state)
        }
        if pending.responseID != pending.command.requestID,
           response.queriedRequestID != pending.command.requestID {
            state.pending?.phase = .uncertain
            state.message = response.error?.watchMessage
                ?? "원래 요청의 결과를 확인하지 못했어요. 같은 요청 상태를 다시 확인해주세요."
            return .merge(.cancel(id: CancelID.delivery), .cancel(id: CancelID.poll))
        }
        return nil
    }

}
