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
        case recording, review, saving, saved, closing, failed, saveFailed
    }

    @ObservableState
    struct State: Equatable {
        let experimentID: UUID
        var recordID: UUID?
        var recordRevision: UInt64?
        var isPreparingStart = false
        var stopWhenStarted = false
        var isRecovering = false
        var phaseBeforeClose: Phase?
        var phase: Phase = .recording
        var failureMessage: String?
        var startedAt: Date?
        var isStopping = false
        var isRetaking = false
        var autoSaveSeconds: Int? = 3
        var shouldDismiss = false
    }

    enum Action {
        case openRequested, presentationEnded, start(UUID, resume: Bool), retryTapped
        case startPrepared(WatchExperimentCommand)
        case startResponse(UUID, WatchExperimentResponse)
        case recordReceived(WatchRecordSnapshot)
        case stopTapped, stopResponse(UUID, WatchExperimentResponse?), stopWaitElapsed(UUID)
        case autoSaveTick(UUID)
        case saveTapped, saveResponse(UUID, WatchExperimentResponse?)
        case retakeTapped, closeTapped
        case cancelFinished(UUID, WatchExperimentResponse?)
    }

    nonisolated enum CancelID: Hashable, Sendable {
        case records(UUID), start(UUID), autoSave(UUID), settle(UUID), stop(UUID), stopWait(UUID)
    }

    let presentationID = UUID()

    @Dependency(\.watchConnectivitySession) private var connectivity
    @Dependency(\.watchExperimentClient) var client
    @Dependency(\.uuid) private var uuid

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .openRequested:
                guard state.recordID == nil, !state.shouldDismiss else { return .none }
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
                    .cancellable(id: CancelID.records(presentationID), cancelInFlight: true),
                    start(pending ?? uuid(), resume: pending != nil, state: &state)
                )

            case let .start(id, resume):
                guard !state.shouldDismiss else { return .none }
                return start(id, resume: resume, state: &state)

            case let .startPrepared(command):
                guard state.isPreparingStart, !state.shouldDismiss,
                      state.recordID == command.requestID else { return .none }
                state.isPreparingStart = false
                return observeStart(
                    experimentID: state.experimentID, recordID: command.requestID, command: command
                )

            case .retryTapped:
                if state.phase == .saveFailed { return .send(.saveTapped) }
                guard state.phase == .failed else { return .none }
                if let id = state.recordID, state.stopWhenStarted {
                    state.phase = .recording
                    state.failureMessage = nil
                    state.isStopping = true
                    return .merge(
                        observeStart(experimentID: state.experimentID, recordID: id, command: nil),
                        stopDeadline(id)
                    )
                }
                if let id = state.recordID, state.startedAt != nil || client.pendingCameraRecord(
                    experimentID: state.experimentID, kind: .video
                ) == id {
                    return .send(.start(id, resume: true))
                }
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
                if state.isPreparingStart { return cancelPreparation(state: &state) }
                state.isStopping = true
                guard state.startedAt != nil else {
                    state.stopWhenStarted = true
                    return stopDeadline(id)
                }
                return .merge(
                    stop(experimentID: state.experimentID, recordID: id), stopDeadline(id)
                )

            case let .stopWaitElapsed(id):
                guard state.recordID == id, state.phase == .recording, state.isStopping else {
                    return .none
                }
                state.isStopping = false
                state.phase = .failed
                state.failureMessage = "iPhone에서 녹화 정지를 확인하지 못했어요."
                return .none

            case let .stopResponse(id, response):
                guard state.recordID == id, !state.shouldDismiss,
                      state.phase == .recording || state.phase == .failed else { return .none }
                state.isStopping = false
                if let record = response?.record, record.phase != .recording {
                    return .send(.recordReceived(record))
                }
                guard response?.phase != .completed else { return .none }
                state.failureMessage = "iPhone에서 녹화 정지를 확인하지 못했어요."
                return failStart(state: &state, recordID: id, clearPending: false)

            case let .autoSaveTick(id):
                guard state.recordID == id, state.phase == .review,
                      let seconds = state.autoSaveSeconds else { return .none }
                state.autoSaveSeconds = seconds - 1
                return seconds == 1 ? .send(.saveTapped) : .none

            case .saveTapped:
                guard state.phase == .review || state.phase == .saveFailed,
                      let id = state.recordID else { return .none }
                state.phase = .saving
                let experimentID = state.experimentID
                return .merge(
                    .cancel(id: CancelID.autoSave(presentationID)),
                    .run { send in
                        let response = try? await client.finishCameraRecord(
                            experimentID: experimentID, recordID: id, kind: .video,
                            operation: .confirmRecord
                        )
                        await send(.saveResponse(id, response))
                    }
                    .cancellable(id: CancelID.settle(presentationID), cancelInFlight: true)
                )

            case let .saveResponse(id, response):
                guard state.recordID == id, !state.shouldDismiss,
                      state.phase == .saving || state.phase == .saveFailed else { return .none }
                let record = response?.record
                if let record, record.phase == .saved || record.phase == .cancelled {
                    return .send(.recordReceived(record))
                }
                if record?.originalRetained == false
                    || (response?.error == .invalidState && record?.originalRetained != true) {
                    return failUnavailableSave(state: &state, recordID: id)
                }
                return failSave(state: &state)

            case .retakeTapped:
                guard state.phase == .review, let id = state.recordID else { return .none }
                state.phaseBeforeClose = state.phase
                state.phase = .closing
                state.isRetaking = true
                return cancelVideo(experimentID: state.experimentID, recordID: id)

            case .closeTapped:
                if state.isPreparingStart { return cancelPreparation(state: &state) }
                guard state.phase != .closing, state.phase != .saving, !state.isStopping
                else { return .none }
                guard state.phase != .saved, state.phase != .failed, state.phase != .saveFailed,
                      let id = state.recordID else {
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

            case .presentationEnded:
                state.shouldDismiss = true
                return .merge(
                    .cancel(id: CancelID.records(presentationID)),
                    .cancel(id: CancelID.start(presentationID)),
                    .cancel(id: CancelID.stop(presentationID)),
                    .cancel(id: CancelID.stopWait(presentationID)),
                    .cancel(id: CancelID.autoSave(presentationID)),
                    .cancel(id: CancelID.settle(presentationID))
                )
            }
        }
    }
}

private extension VideoRecordFeature {
    func applyRecord(_ record: WatchRecordSnapshot, state: inout State) -> Effect<Action> {
        switch record.phase {
        case .recording:
            if state.stopWhenStarted {
                let alreadyTimedOut = state.phase == .failed
                state.startedAt = record.startedAt
                state.isRecovering = false
                state.stopWhenStarted = false
                state.isStopping = true
                state.phase = .recording
                let effect = stop(experimentID: state.experimentID, recordID: record.id)
                return alreadyTimedOut ? .merge(effect, stopDeadline(record.id)) : effect
            }
            if state.phase == .recording || state.phaseBeforeClose == .recording {
                state.startedAt = record.startedAt
                state.isRecovering = false
            }
        case .previewing, .review:
            let recoveringStop = state.phase == .failed
                && (state.stopWhenStarted || state.startedAt != nil)
            state.stopWhenStarted = false
            state.isStopping = false
            if state.phase == .closing {
                state.phaseBeforeClose = .review
                return .none
            }
            guard state.phase == .recording || recoveringStop else { return .none }
            state.phase = .review
            state.autoSaveSeconds = 3
            return .run { send in
                for _ in 0..<3 {
                    try await Task.sleep(for: .seconds(1))
                    await send(.autoSaveTick(record.id))
                }
            }
            .cancellable(id: CancelID.autoSave(presentationID), cancelInFlight: true)
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
            state.failureMessage = "iPhone에서 녹화가 취소됐어요."
            state.startedAt = nil
            return failStart(state: &state, recordID: record.id)
        }
        return .merge(
            .cancel(id: CancelID.start(presentationID)),
            .cancel(id: CancelID.autoSave(presentationID))
        )
    }

    func applyFailure(_ record: WatchRecordSnapshot, state: inout State) -> Effect<Action> {
        guard state.phase != .saved else { return .none }
        if record.originalRetained == false {
            if state.phase == .review || state.phase == .saving || state.phase == .saveFailed {
                return failUnavailableSave(state: &state, recordID: record.id)
            }
            return failStart(state: &state, recordID: record.id)
        }
        if state.phase == .review || state.phase == .saving || state.phase == .saveFailed {
            return failSave(state: &state)
        }
        if record.originalRetained == true {
            if state.phase == .closing {
                state.phaseBeforeClose = .review
            } else {
                state.phase = .review
            }
            state.autoSaveSeconds = nil
        } else if state.phase == .recording {
            state.failureMessage = "이전 녹화 상태를 확인하지 못했어요."
            return failStart(state: &state, recordID: record.id, clearPending: false)
        }
        return .cancel(id: CancelID.autoSave(presentationID))
    }

    func failUnavailableSave(state: inout State, recordID: UUID) -> Effect<Action> {
        state.failureMessage = "iPhone에서 저장할 영상을 확인할 수 없어요."
        return failStart(state: &state, recordID: recordID)
    }

    func failSave(state: inout State) -> Effect<Action> {
        state.phase = .saveFailed
        state.autoSaveSeconds = nil
        state.failureMessage = "영상 저장을 확인하지 못했어요."
        return .cancel(id: CancelID.autoSave(presentationID))
    }

    func cancelVideo(
        experimentID: UUID, recordID: UUID, stopFirst: Bool = false
    ) -> Effect<Action> {
        .merge(
            .cancel(id: CancelID.autoSave(presentationID)),
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
            .cancellable(id: CancelID.settle(presentationID), cancelInFlight: true)
        )
    }
}
