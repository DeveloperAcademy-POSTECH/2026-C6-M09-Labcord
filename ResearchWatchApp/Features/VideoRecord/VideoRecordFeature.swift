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
        case starting, recording, previewing, review, saving, saved, closing, failed, cancelFailed
    }

    @ObservableState
    struct State: Equatable {
        let experimentID: UUID
        var recordID: UUID?
        var phase: Phase = .starting
        var requests = WatchCameraRequests()
        var cancellation: WatchCameraCancellation?
        var startedAt: Date?
        var isStopping = false
        var autoSaveSeconds: Int? = 3
        var shouldDismiss = false
    }

    enum Action {
        case appeared, disappeared, retryTapped, recordReceived(WatchRecordSnapshot)
        case requestEvent(UUID, WatchCameraRequestEvent)
        case stopTapped, saveTapped, retakeTapped, closeTapped, autoSaveTick(UUID)
    }

    private nonisolated enum CancelID: Hashable, Sendable {
        case records, request, autoSave
    }

    @Dependency(\.watchConnectivitySession) private var connectivity
    @Dependency(\.watchExperimentClient) private var client
    @Dependency(\.uuid) private var uuid

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .appeared:
                let initial = state.recordID == nil ? start(&state) : .none
                return .merge(initial, .run { send in
                    await connectivity.activate()
                    for await record in await connectivity.records.stream() {
                        await send(.recordReceived(record))
                    }
                }
                .cancellable(id: CancelID.records, cancelInFlight: true))

            case .retryTapped:
                if state.phase == .cancelFailed { return cancel(&state) }
                guard state.phase == .failed else { return .none }
                if state.requests.lastRecord?.originalRetained == false,
                   state.requests.lastRecord?.phase == .failed { return start(&state) }
                state.phase = .starting
                return request(.startVideo, state: &state)

            case let .requestEvent(id, event):
                guard let operation = state.requests.receive(event, from: id) else { return .none }
                switch event {
                case .prepared, .rejected: return .none
                case let .received(record): return .send(.recordReceived(record))
                case let .failed(error):
                    return requestFailed(operation, error: error, state: &state)
                }

            case let .recordReceived(record):
                return receive(record, state: &state)

            case .stopTapped:
                guard state.phase == .recording, !state.isStopping else { return .none }
                state.isStopping = true
                return request(.stopVideo, state: &state)

            case let .autoSaveTick(id):
                guard state.recordID == id, state.phase == .review,
                      let seconds = state.autoSaveSeconds else { return .none }
                state.autoSaveSeconds = seconds - 1
                return seconds == 1 ? .send(.saveTapped) : .none

            case .saveTapped:
                let canRetry = state.phase == .saving
                    && !state.requests.isWaiting(for: .confirmRecord)
                guard [.previewing, .review].contains(state.phase) || canRetry else {
                    return .none
                }
                state.phase = .saving
                return .merge(
                    .cancel(id: CancelID.autoSave), request(.confirmRecord, state: &state)
                )

            case .retakeTapped:
                guard [.previewing, .review].contains(state.phase) else { return .none }
                state.cancellation = .retake
                return cancel(&state)

            case .closeTapped:
                guard state.phase != .closing else { return .none }
                guard state.phase != .saved, state.requests.mayHaveCaptured else {
                    state.shouldDismiss = true
                    return .cancel(id: CancelID.request)
                }
                state.cancellation = .close
                return cancel(&state)

            case .disappeared:
                return .merge(
                    .cancel(id: CancelID.records), .cancel(id: CancelID.autoSave),
                    .cancel(id: CancelID.request)
                )
            }
        }
    }
}

private extension VideoRecordFeature {
    func start(_ state: inout State) -> Effect<Action> {
        state.recordID = uuid()
        state.phase = .starting
        state.startedAt = nil
        state.isStopping = false
        state.requests = WatchCameraRequests()
        state.cancellation = nil
        state.autoSaveSeconds = nil
        return request(.startVideo, state: &state)
    }

    func cancel(_ state: inout State) -> Effect<Action> {
        state.phase = .closing
        state.autoSaveSeconds = nil
        let phase = state.requests.lastRecord?.phase
        let stopFirst = phase == nil || phase == .recording
        return .merge(
            .cancel(id: CancelID.autoSave),
            request(stopFirst ? .stopVideo : .cancelRecord, state: &state)
        )
    }

    func request(
        _ operation: WatchExperimentCommand.Operation, state: inout State
    ) -> Effect<Action> {
        guard let recordID = state.recordID else { return .none }
        let attempt = state.requests.begin(
            operation, id: uuid(), experimentID: state.experimentID,
            recordID: recordID, kind: .video
        )
        return .run { send in
            await attempt.run(using: client) { await send(.requestEvent(attempt.id, $0)) }
        }
        .cancellable(id: CancelID.request, cancelInFlight: true)
    }

    func requestFailed(
        _ operation: WatchExperimentCommand.Operation,
        error: WatchExperimentError, state: inout State
    ) -> Effect<Action> {
        if state.phase == .closing {
            if operation == .stopVideo, error == .invalidState {
                return request(.cancelRecord, state: &state)
            }
            state.phase = .cancelFailed
        } else if operation == .startVideo, state.phase == .starting {
            state.phase = .failed
        } else if operation == .stopVideo {
            state.isStopping = false
        } else if operation == .confirmRecord, state.phase == .saving {
            state.phase = .review
            state.autoSaveSeconds = nil
        }
        return .none
    }

    func receive(_ record: WatchRecordSnapshot, state: inout State) -> Effect<Action> {
        guard !state.shouldDismiss, record.kind == .video, record.id == state.recordID,
              record.experimentID == state.experimentID, state.requests.accept(record)
        else { return .none }
        switch record.phase {
        case .cancelled:
            if state.cancellation == .retake { return start(&state) }
            state.shouldDismiss = true
        case .saved:
            state.phase = .saved
        case .recording:
            receiveRecording(record, state: &state)
            return .none
        case .review, .previewing:
            return review(record, state: &state)
        case .saving:
            guard state.cancellation == nil else { return .none }
            state.phase = .saving
        case .failed:
            state.isStopping = false
            state.phase = failurePhase(record, cancellation: state.cancellation)
        default: return .none
        }
        state.autoSaveSeconds = nil
        return .cancel(id: CancelID.autoSave)
    }

    func failurePhase(
        _ record: WatchRecordSnapshot, cancellation: WatchCameraCancellation?
    ) -> Phase {
        guard cancellation == nil else { return .cancelFailed }
        return record.originalRetained == true ? .review : .failed
    }

    func receiveRecording(_ record: WatchRecordSnapshot, state: inout State) {
        guard state.cancellation == nil,
              [.starting, .failed, .recording].contains(state.phase) else { return }
        state.phase = .recording
        state.startedAt = record.startedAt
    }

    func review(_ record: WatchRecordSnapshot, state: inout State) -> Effect<Action> {
        state.isStopping = false
        if state.cancellation != nil {
            guard state.phase == .closing || state.phase == .cancelFailed,
                  !state.requests.isWaiting(for: .cancelRecord) else { return .none }
            return cancel(&state)
        }
        guard [.starting, .failed, .recording, .previewing].contains(state.phase) else {
            return .none
        }
        state.autoSaveSeconds = record.canAutoSave == false ? nil : 3
        state.phase = record.phase == .previewing && state.autoSaveSeconds == nil
            ? .previewing : .review
        guard state.autoSaveSeconds != nil else { return .none }
        return .run { send in
            for _ in 0..<3 {
                try await Task.sleep(for: .seconds(1))
                await send(.autoSaveTick(record.id))
            }
        }
        .cancellable(id: CancelID.autoSave, cancelInFlight: true)
    }
}
