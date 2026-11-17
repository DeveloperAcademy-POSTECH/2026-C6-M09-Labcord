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
        var phase: Phase = .recording
        var startedAt: Date?
        var isStopping = false
        var isRetaking = false
        var autoSaveSeconds: Int? = 3
        var shouldDismiss = false
    }

    enum Action {
        case appeared, disappeared, start(UUID)
        case startResponse(UUID, WatchExperimentResponse?)
        case recordReceived(WatchRecordSnapshot)
        case stopTapped, stopResponse(UUID, WatchExperimentResponse?)
        case autoSaveTick(UUID)
        case saveTapped, saveResponse(UUID, WatchExperimentResponse?)
        case retakeTapped, retakeFinished(UUID, Bool)
        case closeTapped, closeFinished(Bool)
    }

    private nonisolated enum CancelID: Hashable, Sendable {
        case records, start, autoSave
    }

    @Dependency(\.watchConnectivitySession) private var connectivity
    @Dependency(\.watchExperimentClient) private var client
    @Dependency(\.uuid) private var uuid

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .appeared:
                return .merge(
                    .run { send in
                        await connectivity.activate()
                        for await record in await connectivity.records.stream() {
                            await send(.recordReceived(record))
                        }
                    }
                    .cancellable(id: CancelID.records, cancelInFlight: true),
                    .send(.start(uuid()))
                )

            case let .start(id):
                guard !state.shouldDismiss else { return .none }
                state.recordID = id
                state.phase = .recording
                state.startedAt = nil
                state.isStopping = false
                state.isRetaking = false
                state.autoSaveSeconds = 3
                let experimentID = state.experimentID
                return .run { send in
                    let response = try? await client.startWatchVideo(
                        experimentID: experimentID, recordID: id
                    )
                    await send(.startResponse(id, response))
                }
                .cancellable(id: CancelID.start, cancelInFlight: true)

            case let .startResponse(id, response):
                guard state.recordID == id, state.phase == .recording else { return .none }
                if let record = response?.record { return .send(.recordReceived(record)) }
                if response == nil || response?.phase == .failed { state.phase = .failed }
                return .none

            case let .recordReceived(record):
                guard record.experimentID == state.experimentID,
                      record.id == state.recordID, record.kind == .video,
                      !state.shouldDismiss else { return .none }
                switch record.phase {
                case .recording:
                    guard state.phase == .recording else { return .none }
                    state.startedAt = record.startedAt
                    return .none
                case .previewing, .review:
                    guard state.phase == .recording else { return .none }
                    state.phase = .review
                    state.autoSaveSeconds = 3
                    let id = record.id
                    return .run { send in
                        for _ in 0..<3 {
                            try await Task.sleep(for: .seconds(1))
                            await send(.autoSaveTick(id))
                        }
                    }
                    .cancellable(id: CancelID.autoSave, cancelInFlight: true)
                case .saving:
                    state.phase = .saving
                    return .cancel(id: CancelID.autoSave)
                case .saved:
                    state.phase = .saved
                    return .cancel(id: CancelID.autoSave)
                case .cancelled:
                    if !state.isRetaking { state.shouldDismiss = true }
                    return .cancel(id: CancelID.autoSave)
                case .failed:
                    if record.originalRetained == true {
                        state.phase = .review
                        state.autoSaveSeconds = nil
                    } else {
                        state.phase = .failed
                    }
                    return .cancel(id: CancelID.autoSave)
                default:
                    return .none
                }

            case .stopTapped:
                guard state.phase == .recording, !state.isStopping,
                      state.startedAt != nil, let id = state.recordID else { return .none }
                state.isStopping = true
                let experimentID = state.experimentID
                return .run { send in
                    let response = try? await client.finishWatchVideo(
                        experimentID: experimentID, recordID: id, operation: .stopVideo
                    )
                    await send(.stopResponse(id, response))
                }

            case let .stopResponse(id, response):
                guard state.recordID == id else { return .none }
                if let record = response?.record { return .send(.recordReceived(record)) }
                if state.phase == .recording { state.isStopping = false }
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
                        let response = try? await client.finishWatchVideo(
                            experimentID: experimentID, recordID: id, operation: .confirmRecord
                        )
                        await send(.saveResponse(id, response))
                    }
                )

            case let .saveResponse(id, response):
                guard state.recordID == id, state.phase == .saving else { return .none }
                if let record = response?.record { return .send(.recordReceived(record)) }
                state.phase = .review
                state.autoSaveSeconds = nil
                return .none

            case .retakeTapped:
                guard state.phase == .review, let id = state.recordID else { return .none }
                state.phase = .closing
                state.isRetaking = true
                let experimentID = state.experimentID
                let nextID = uuid()
                return .merge(
                    .cancel(id: CancelID.autoSave),
                    .run { send in
                        let cancelled = await client.cancelWatchVideo(
                            experimentID: experimentID, recordID: id
                        )
                        await send(.retakeFinished(nextID, cancelled))
                    }
                )

            case let .retakeFinished(id, cancelled):
                guard state.phase == .closing else { return .none }
                if cancelled { return .send(.start(id)) }
                state.phase = .review
                state.autoSaveSeconds = nil
                return .none

            case .closeTapped:
                guard state.phase != .closing else { return .none }
                guard state.phase != .saved, let id = state.recordID else {
                    state.shouldDismiss = true
                    return .none
                }
                let wasRecording = state.phase == .recording
                state.phase = .closing
                state.isRetaking = false
                let experimentID = state.experimentID
                return .merge(
                    .cancel(id: CancelID.autoSave),
                    .run { send in
                        if wasRecording {
                            _ = try? await client.finishWatchVideo(
                                experimentID: experimentID, recordID: id,
                                operation: .stopVideo
                            )
                        }
                        let cancelled = await client.cancelWatchVideo(
                            experimentID: experimentID, recordID: id
                        )
                        await send(.closeFinished(cancelled))
                    }
                )

            case let .closeFinished(cancelled):
                guard state.phase == .closing else { return .none }
                if cancelled {
                    state.shouldDismiss = true
                } else {
                    state.phase = .review
                    state.autoSaveSeconds = nil
                }
                return .none

            case .disappeared:
                return .merge(
                    .cancel(id: CancelID.records),
                    .cancel(id: CancelID.start),
                    .cancel(id: CancelID.autoSave)
                )
            }
        }
    }
}

private extension WatchExperimentClient {
    func startWatchVideo(experimentID: UUID, recordID: UUID) async throws
        -> WatchExperimentResponse {
        let current = try await videoSnapshot(experimentID)
        let preparation = try await videoSendAndWait(WatchExperimentCommand(
            operation: .prepareStart, experimentID: experimentID,
            expectedRevision: current.revision
        ))
        guard let token = preparation.startToken else {
            throw WatchExperimentError.resultUnknown
        }
        try Task.checkCancellation()
        return try await videoSendAndWait(WatchExperimentCommand(
            requestID: recordID, operation: .startVideo, experimentID: experimentID,
            expectedRevision: preparation.snapshot?.revision ?? current.revision,
            targetID: recordID, startToken: token
        ), returnWhenRecording: true)
    }

    func finishWatchVideo(
        experimentID: UUID, recordID: UUID, operation: WatchExperimentCommand.Operation
    ) async throws -> WatchExperimentResponse {
        let current = try await videoSnapshot(experimentID)
        return try await videoSendAndWait(WatchExperimentCommand(
            operation: operation, experimentID: experimentID,
            expectedRevision: current.revision, targetID: recordID
        ))
    }

    func cancelWatchVideo(experimentID: UUID, recordID: UUID) async -> Bool {
        let immediate = WatchExperimentCommand(
            operation: .cancelRecord, experimentID: experimentID, targetID: recordID
        )
        if let response = try? await videoSendAndWait(immediate), response.phase == .completed {
            return true
        }
        for _ in 0..<20 {
            if let response = try? await finishWatchVideo(
                experimentID: experimentID, recordID: recordID, operation: .cancelRecord
            ), response.phase == .completed { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    func videoSnapshot(_ experimentID: UUID) async throws -> WatchExperimentSnapshot {
        let response = try await send(WatchExperimentCommand(
            operation: .snapshot, experimentID: experimentID
        ))
        guard response.phase == .completed, let snapshot = response.snapshot else {
            throw response.error ?? WatchExperimentError.resultUnknown
        }
        return snapshot
    }

    func videoSendAndWait(
        _ command: WatchExperimentCommand, returnWhenRecording: Bool = false
    ) async throws -> WatchExperimentResponse {
        var response = try await send(command)
        for _ in 0..<30 {
            if response.phase == .failed || response.phase == .unknown {
                throw response.error ?? WatchExperimentError.resultUnknown
            }
            if response.phase == .completed || returnWhenRecording
                && response.record?.phase == .recording { return response }
            try await Task.sleep(for: .milliseconds(100))
            response = try await send(WatchExperimentCommand(
                operation: .requestStatus, experimentID: command.experimentID,
                targetID: command.requestID
            ))
        }
        throw WatchExperimentError.deliveryTimeout
    }
}
