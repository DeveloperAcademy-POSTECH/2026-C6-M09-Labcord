import ComposableArchitecture
import Foundation
import LabcordShared

extension WatchExperimentFeature {
    func cancelPendingPhoto(
        _ recordID: UUID, experimentID: UUID, state: inout State
    ) -> Effect<Action>? {
        guard state.selectedID == experimentID, state.isVisible, state.streamID != nil,
              !state.isPreparingInterruption, let pending = state.pending else { return nil }
        if pending.command.operation == .prepareStart,
           state.authorization?.operation == .takePhoto,
           state.authorization?.targetID == recordID {
            state.pending = nil
            state.authorization = nil
            state.startToken = nil
            return .concatenate(
                cancelPhotoRequestEffects(),
                .send(.recording(.preparationCancelled(recordID)))
            )
        }
        guard pending.command.operation == .takePhoto,
              pending.command.experimentID == experimentID,
              pending.command.targetID == recordID else { return nil }
        let cancellation = WatchExperimentCommand(
            requestID: uuid(), operation: .cancelRecord, experimentID: experimentID,
            expectedRevision: state.snapshot?.revision ?? pending.command.expectedRevision,
            targetID: recordID
        )
        do {
            try pendingJournal.supersedeCapture(with: cancellation)
        } catch {
            state.message = "촬영 취소 요청을 보관하지 못했어요. 기존 요청을 유지하고 다시 확인해주세요."
            return .send(.recording(.commandFailed(
                recordID, state.message ?? WatchExperimentError.storageFailed.watchMessage
            )))
        }
        state.pending = PendingRequest(
            command: cancellation, responseID: cancellation.requestID,
            phase: state.isReachable ? .delivering : .uncertain
        )
        state.authorization = nil
        state.canRetryPendingCancellation = !state.isReachable
        state.clearMessageUnlessInterruptionUnconfirmed()
        guard state.isReachable else {
            state.message = "취소 요청을 보관했어요. 연결 후 같은 요청의 결과를 확인해주세요."
            return .merge(
                cancelPhotoRequestEffects(),
                .send(.recording(.commandFailed(
                    recordID, state.message ?? WatchExperimentError.storageFailed.watchMessage
                )))
            )
        }
        return .concatenate(
            cancelPhotoRequestEffects(),
            .merge(send(cancellation), deliveryDeadline(cancellation.requestID))
        )
    }

    func retryPendingCancellation(state: inout State) -> Effect<Action> {
        guard state.isVisible, state.streamID != nil, state.isReachable,
              state.canRetryPendingCancellation, let pending = state.pending,
              pending.command.operation == .cancelRecord, pending.phase == .uncertain else {
            return .none
        }
        do {
            guard try pendingJournal.load() == pending.command else {
                throw WatchExperimentError.duplicateConflict
            }
        } catch {
            state.message = "보관된 취소 요청을 확인하지 못했어요. 기존 요청을 유지해요."
            return .none
        }
        state.pending?.responseID = pending.command.requestID
        state.pending?.phase = .delivering
        state.canRetryPendingCancellation = false
        state.clearMessageUnlessInterruptionUnconfirmed()
        return .concatenate(
            cancelPhotoRequestEffects(),
            .merge(send(pending.command), deliveryDeadline(pending.command.requestID))
        )
    }

    func recoverCaptureAfterCancellationFailure(
        _ command: WatchExperimentCommand, state: inout State
    ) -> Effect<Action>? {
        do {
            guard let original = try pendingJournal.restoreCapture(after: command.requestID) else {
                return nil
            }
            state.pending = PendingRequest(
                command: original, responseID: original.requestID, phase: .uncertain
            )
            state.canRetryPendingCancellation = false
            state.message = "취소하지 못했어요. 원래 촬영 요청의 결과를 먼저 확인해주세요."
            let record: Effect<Action> = original.targetID.map {
                .send(.recording(.commandFailed(
                    $0, state.message ?? WatchExperimentError.storageFailed.watchMessage
                )))
            } ?? .none
            return .concatenate(
                .merge(cancelPhotoRequestEffects(), record), .send(.checkRequest)
            )
        } catch {
            state.pending?.phase = .uncertain
            state.message = "취소 실패 후 원래 요청을 복구하지 못했어요. 보관된 요청은 유지해요."
            return cancelPhotoRequestEffects()
        }
    }

    private func cancelPhotoRequestEffects() -> Effect<Action> {
        .merge(
            .cancel(id: CancelID.request), .cancel(id: CancelID.delivery),
            .cancel(id: CancelID.poll)
        )
    }
}
