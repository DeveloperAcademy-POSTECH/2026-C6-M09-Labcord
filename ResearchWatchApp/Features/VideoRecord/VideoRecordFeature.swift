//
//  VideoRecordFeature.swift
//  Researchers
//
//  Created by 정홍섭 on 11/17/26.
//

import ComposableArchitecture
import Foundation
import LabcordShared
import LabcordWatchOS

@Reducer
struct VideoRecordFeature {
    enum Phase: Equatable {
        case recording, review, saving, saved, closing, failed
    }

    @ObservableState
    struct State: Equatable {
        let experimentID: UUID
        var recordID: UUID?
        var recordRevision: UInt64?
        var isRecovering = false
        var shouldRetryStopOnStart = false
        var phaseBeforeClose: Phase?
        var phase: Phase = .recording
        var startedAt: Date?
        var isStopping = false
        var isRetaking = false
        var autoSaveSeconds: Int? = 3
        var shouldDismiss = false
    }

    enum Action {
        case appeared, disappeared, start(UUID, resume: Bool), retryTapped
        case startResponse(UUID, WatchExperimentResponse)
        case recordReceived(WatchRecordSnapshot)
        case stopTapped, stopResponse(UUID, WatchExperimentResponse?)
        case autoSaveTick(UUID)
        case saveTapped, saveResponse(UUID, WatchExperimentResponse?)
        case retakeTapped, closeTapped
        case cancelFinished(UUID, WatchExperimentResponse?)
    }

    private nonisolated enum CancelID: Hashable, Sendable {
        case records, start, autoSave, settle, stop
    }

    @Dependency(\.watchConnectivitySession) private var connectivity
    @Dependency(\.watchExperimentClient) private var client
    @Dependency(\.uuid) private var uuid

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .appeared:
                let pending = client.pendingCameraRecord(
                    experimentID: state.experimentID, kind: .video
                )
                return .merge(
                    .run { send in
                        await connectivity.activate()
                        for await record in await connectivity.records.stream() {
                            await send(.recordReceived(record))
                        }
                    }
                    .cancellable(id: CancelID.records, cancelInFlight: true),
                    .send(.start(pending ?? uuid(), resume: pending != nil))
                )

            case let .start(id, resume):
                guard !state.shouldDismiss else { return .none }
                state.recordID = id
                state.recordRevision = nil
                state.isRecovering = resume
                state.shouldRetryStopOnStart = false
                state.phase = .recording
                state.startedAt = nil
                state.isStopping = false
                state.isRetaking = false
                state.autoSaveSeconds = 3
                let experimentID = state.experimentID
                return .run { send in
                    if !resume {
                        do {
                            let response = try await client.startCameraRecord(
                                experimentID: experimentID, recordID: id, kind: .video
                            )
                            await send(.startResponse(id, response))
                        } catch {
                            guard !Task.isCancelled else { return }
                            await send(.startResponse(id, .init(requestID: id, phase: .failed)))
                        }
                    }
                    for await response in await client.cameraRecordUpdates(
                        experimentID: experimentID, recordID: id, kind: .video
                    ) {
                        await send(.startResponse(id, response))
                    }
                }
                .cancellable(id: CancelID.start, cancelInFlight: true)

            case .retryTapped:
                guard state.phase == .failed else { return .none }
                return .send(.start(uuid(), resume: false))

            case let .startResponse(id, response):
                guard state.recordID == id, !state.shouldDismiss else { return .none }
                if let record = response.record { return .send(.recordReceived(record)) }
                guard state.phase == .recording else { return .none }
                if response.phase == .failed && response.error != .resultUnknown
                    || response.error == .requestExpired {
                    return failStart(state: &state, recordID: id)
                }
                if state.startedAt == nil,
                   response.phase == .unknown || response.error == .resultUnknown {
                    state.isRecovering = true
                }
                return .none

            case let .recordReceived(record):
                guard record.experimentID == state.experimentID,
                      record.id == state.recordID, record.kind == .video,
                      !state.shouldDismiss else { return .none }
                if let previous = state.recordRevision, (record.revision ?? 0) <= previous {
                    return .none
                }
                state.recordRevision = record.revision
                return applyRecord(record, state: &state)

            case .stopTapped:
                guard state.phase == .recording, !state.isStopping,
                      let id = state.recordID else { return .none }
                state.isStopping = true
                state.shouldRetryStopOnStart = state.startedAt == nil
                let experimentID = state.experimentID
                return .run { send in
                    let response = try? await client.finishCameraRecord(
                        experimentID: experimentID, recordID: id, kind: .video,
                        operation: .stopVideo
                    )
                    await send(.stopResponse(id, response))
                }
                .cancellable(id: CancelID.stop, cancelInFlight: true)

            case let .stopResponse(id, response):
                guard state.recordID == id else { return .none }
                state.isStopping = false
                if let record = response?.record, record.phase != .recording {
                    return .send(.recordReceived(record))
                }
                if state.phase == .recording, state.shouldRetryStopOnStart,
                   state.startedAt != nil, response?.phase != .completed {
                    state.shouldRetryStopOnStart = false
                    return .send(.stopTapped)
                }
                if response?.phase == .completed { state.shouldRetryStopOnStart = false }
                return .none

            case let .autoSaveTick(id):
                guard state.recordID == id, state.phase == .review,
                      let seconds = state.autoSaveSeconds else { return .none }
                state.autoSaveSeconds = seconds - 1
                return seconds == 1 ? .send(.saveTapped) : .none

            case .saveTapped:
                guard state.phase == .review, let id = state.recordID else { return .none }
                state.phase = .saving
                let experimentID = state.experimentID
                return .merge(
                    .cancel(id: CancelID.autoSave),
                    .run { send in
                        let response = try? await client.finishCameraRecord(
                            experimentID: experimentID, recordID: id, kind: .video,
                            operation: .confirmRecord
                        )
                        await send(.saveResponse(id, response))
                    }
                    .cancellable(id: CancelID.settle, cancelInFlight: true)
                )

            case let .saveResponse(id, response):
                guard state.recordID == id, state.phase == .saving else { return .none }
                if let record = response?.record, record.phase == .saved {
                    return .send(.recordReceived(record))
                }
                state.phase = .review
                state.autoSaveSeconds = nil
                return .none

            case .retakeTapped:
                guard state.phase == .review, let id = state.recordID else { return .none }
                state.phaseBeforeClose = state.phase
                state.phase = .closing
                state.isRetaking = true
                return cancelVideo(experimentID: state.experimentID, recordID: id)

            case .closeTapped:
                guard state.phase != .closing, state.phase != .saving, !state.isStopping
                else { return .none }
                guard state.phase != .saved, state.phase != .failed, let id = state.recordID else {
                    state.shouldDismiss = true
                    return .none
                }
                state.phaseBeforeClose = state.phase
                state.phase = .closing
                state.isRetaking = false
                return cancelVideo(
                    experimentID: state.experimentID, recordID: id,
                    stopFirst: state.phaseBeforeClose == .recording
                )

            case let .cancelFinished(id, response):
                guard state.phase == .closing, state.recordID == id else { return .none }
                if response?.phase == .completed, response?.record?.phase == .cancelled {
                    client.clearPendingCameraRecord(
                        experimentID: state.experimentID, kind: .video, recordID: id
                    )
                    if state.isRetaking { return .send(.start(uuid(), resume: false)) }
                    state.shouldDismiss = true
                } else if let record = response?.record, record.phase == .saved {
                    return .send(.recordReceived(record))
                } else if !state.isRetaking, state.isRecovering, state.startedAt == nil {
                    state.shouldDismiss = true
                } else {
                    state.phase = state.phaseBeforeClose ?? .recording
                    state.autoSaveSeconds = nil
                }
                return .none

            case .disappeared:
                return .merge(
                    .cancel(id: CancelID.records),
                    .cancel(id: CancelID.start), .cancel(id: CancelID.stop),
                    .cancel(id: CancelID.autoSave), .cancel(id: CancelID.settle)
                )
            }
        }
    }
}

private extension VideoRecordFeature {
    func failStart(state: inout State, recordID: UUID) -> Effect<Action> {
        client.clearPendingCameraRecord(
            experimentID: state.experimentID, kind: .video, recordID: recordID
        )
        state.phase = .failed
        state.isStopping = false
        return .merge(.cancel(id: CancelID.start), .cancel(id: CancelID.autoSave))
    }

    func applyRecord(_ record: WatchRecordSnapshot, state: inout State) -> Effect<Action> {
        switch record.phase {
        case .recording:
            if state.phase == .recording || state.phaseBeforeClose == .recording {
                state.startedAt = record.startedAt
                state.isRecovering = false
            }
            if state.phase == .recording, state.shouldRetryStopOnStart, !state.isStopping {
                state.shouldRetryStopOnStart = false
                return .send(.stopTapped)
            }
        case .previewing, .review:
            state.isStopping = false
            if state.phase == .closing {
                state.phaseBeforeClose = .review
                return .none
            }
            guard state.phase == .recording else { return .none }
            state.phase = .review
            state.autoSaveSeconds = 3
            return .run { send in
                for _ in 0..<3 {
                    try await Task.sleep(for: .seconds(1))
                    await send(.autoSaveTick(record.id))
                }
            }
            .cancellable(id: CancelID.autoSave, cancelInFlight: true)
        case .saved, .cancelled:
            return finishRecord(record, state: &state)
        case .failed:
            return applyFailure(record, state: &state)
        default:
            break
        }
        return .none
    }

    func finishRecord(
        _ record: WatchRecordSnapshot, state: inout State
    ) -> Effect<Action> {
        client.clearPendingCameraRecord(
            experimentID: state.experimentID, kind: .video, recordID: record.id
        )
        if record.phase == .saved {
            state.phase = .saved
        } else if state.phase != .closing {
            state.shouldDismiss = true
        }
        return .merge(.cancel(id: CancelID.start), .cancel(id: CancelID.autoSave))
    }

    func applyFailure(_ record: WatchRecordSnapshot, state: inout State) -> Effect<Action> {
        if record.originalRetained == false {
            return failStart(state: &state, recordID: record.id)
        }
        if record.originalRetained == true {
            if state.phase == .closing {
                state.phaseBeforeClose = .review
            } else {
                state.phase = .review
            }
            state.autoSaveSeconds = nil
        } else if state.phase == .recording {
            state.isRecovering = true
            state.startedAt = nil
        }
        return .cancel(id: CancelID.autoSave)
    }

    func cancelVideo(
        experimentID: UUID, recordID: UUID, stopFirst: Bool = false
    ) -> Effect<Action> {
        .merge(
            .cancel(id: CancelID.autoSave),
            .run { send in
                if stopFirst {
                    _ = try? await client.finishCameraRecord(
                        experimentID: experimentID, recordID: recordID, kind: .video,
                        operation: .stopVideo
                    )
                }
                guard !Task.isCancelled else { return }
                let response = try? await client.finishCameraRecord(
                    experimentID: experimentID, recordID: recordID, kind: .video,
                    operation: .cancelRecord
                )
                await send(.cancelFinished(recordID, response))
            }
            .cancellable(id: CancelID.settle, cancelInFlight: true)
        )
    }
}
