import ComposableArchitecture
import Foundation
import LabcordShared
import LabcordWatchOS

extension VideoRecordFeature {
    func start(_ id: UUID, resume: Bool, state: inout State) -> Effect<Action> {
        state.recordID = id
        state.recordRevision = nil
        state.isRecovering = resume
        state.phase = .recording
        state.failureMessage = nil
        state.phaseBeforeClose = nil
        state.startedAt = nil
        state.isStopping = false
        state.isRetaking = false
        state.autoSaveSeconds = 3
        state.isPreparingStart = !resume
        state.stopWhenStarted = false
        let experimentID = state.experimentID
        if resume { return observeStart(experimentID: experimentID, recordID: id, command: nil) }
        return .run { send in
            do {
                let command = try await client.prepareCameraRecord(
                    experimentID: experimentID, recordID: id, kind: .video
                )
                await send(.startPrepared(command))
            } catch {
                guard !Task.isCancelled else { return }
                await send(.startResponse(id, .init(requestID: id, phase: .failed)))
            }
        }
        .cancellable(id: CancelID.start(presentationID), cancelInFlight: true)
    }

    func observeStart(
        experimentID: UUID, recordID: UUID, command: WatchExperimentCommand?
    ) -> Effect<Action> {
        .run { send in
            if let command {
                do {
                    let response = try await client.startPreparedCameraRecord(command)
                    await send(.startResponse(recordID, response))
                } catch {
                    guard !Task.isCancelled else { return }
                    let failure = WatchExperimentResponse(requestID: recordID, phase: .failed)
                    await send(.startResponse(recordID, failure))
                }
            }
            for await response in await client.cameraRecordUpdates(
                experimentID: experimentID, recordID: recordID, kind: .video
            ) {
                await send(.startResponse(recordID, response))
            }
        }
        .cancellable(id: CancelID.start(presentationID), cancelInFlight: true)
    }

    func cancelPreparation(state: inout State) -> Effect<Action> {
        state.isPreparingStart = false
        state.shouldDismiss = true
        return .cancel(id: CancelID.start(presentationID))
    }

    func stopDeadline(_ id: UUID) -> Effect<Action> {
        .run { send in
            try await Task.sleep(for: .seconds(3))
            await send(.stopWaitElapsed(id))
        }
        .cancellable(id: CancelID.stopWait(presentationID), cancelInFlight: true)
    }

    func stop(experimentID: UUID, recordID: UUID) -> Effect<Action> {
        .run { send in
            let response = try? await client.finishCameraRecord(
                experimentID: experimentID, recordID: recordID, kind: .video, operation: .stopVideo
            )
            await send(.stopResponse(recordID, response))
        }
        .cancellable(id: CancelID.stop(presentationID), cancelInFlight: true)
    }

    func failStart(
        state: inout State, recordID: UUID, clearPending: Bool = true
    ) -> Effect<Action> {
        if clearPending {
            client.clearPendingCameraRecord(
                experimentID: state.experimentID, kind: .video, recordID: recordID
            )
        }
        state.phase = .failed
        state.isPreparingStart = false
        state.stopWhenStarted = false
        state.isStopping = false
        return .merge(
            .cancel(id: CancelID.start(presentationID)),
            .cancel(id: CancelID.autoSave(presentationID))
        )
    }
}
