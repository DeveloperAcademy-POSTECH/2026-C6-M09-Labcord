import ComposableArchitecture
import Foundation
import LabcordShared
import LabcordWatchOS

@Reducer
struct PhotoRecordFeature {
    enum Phase: Equatable {
        case capturing, recovering, review, saving, saved, closing, failed
    }

    @ObservableState
    struct State: Equatable {
        let experimentID: UUID
        var recordID: UUID?
        var recordRevision: UInt64?
        var phoneScreen: WatchScreenSnapshot?
        var phase: Phase = .capturing
        var phaseBeforeClose: Phase?
        var autoSaveSeconds: Int? = 3
        var shouldDismiss = false
    }

    enum Action {
        case openRequested, presentationEnded, recordReceived(WatchRecordSnapshot)
        case screenReceived(WatchScreenSnapshot)
        case captureResponse(UUID, WatchExperimentResponse), captureWaitElapsed(UUID)
        case saveTapped, saveResponse(UUID, WatchExperimentResponse?)
        case retakeTapped, retryTapped
        case closeTapped, cancelFinished(UUID, retake: Bool, WatchExperimentResponse?)
        case autoSaveTick(UUID)
    }

    private nonisolated enum CancelID: Hashable, Sendable {
        case screens(UUID), records(UUID), autoSave(UUID)
        case capture(UUID), settle(UUID), captureWait(UUID)
    }

    private let presentationID = UUID()

    @Dependency(\.watchConnectivitySession) private var connectivity
    @Dependency(\.watchExperimentClient) private var client
    @Dependency(\.uuid) private var uuid

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .openRequested:
                guard state.recordID == nil, !state.shouldDismiss else { return .none }
                let pending = client.pendingCameraRecord(
                    experimentID: state.experimentID, kind: .photo
                )
                return .merge(
                    .run { send in
                        await connectivity.activate()
                        for await record in await connectivity.records.stream() {
                            await send(.recordReceived(record))
                        }
                    }
                    .cancellable(id: CancelID.records(presentationID), cancelInFlight: true),
                    .run { send in
                        for await screen in await client.screens() {
                            await send(.screenReceived(screen))
                        }
                    }
                    .cancellable(id: CancelID.screens(presentationID), cancelInFlight: true),
                    start(pending ?? uuid(), resume: pending != nil, state: &state)
                )

            case let .screenReceived(screen):
                state.receiveScreen(screen)
                return .none

            case let .captureWaitElapsed(id):
                if state.recordID == id, state.phase == .capturing { state.phase = .recovering }
                return .none

            case let .captureResponse(id, response):
                guard state.recordID == id, !state.shouldDismiss else { return .none }
                if let screen = response.screen { state.receiveScreen(screen) }
                if let record = response.record { return .send(.recordReceived(record)) }
                guard state.phase == .capturing || state.phase == .recovering else { return .none }
                if response.phase == .failed && response.error != .resultUnknown
                    || response.error == .requestExpired {
                    return failCapture(state: &state, recordID: id)
                }
                if response.phase == .unknown || response.error == .resultUnknown {
                    state.phase = .recovering
                }
                return .none

            case let .recordReceived(record):
                guard record.experimentID == state.experimentID,
                      record.id == state.recordID, record.kind == .photo,
                      !state.shouldDismiss else { return .none }
                if let previous = state.recordRevision, (record.revision ?? 0) <= previous {
                    return .none
                }
                state.recordRevision = record.revision
                return applyRecord(record, state: &state)

            case let .autoSaveTick(id):
                guard state.recordID == id, state.phase == .review,
                      let seconds = state.autoSaveSeconds else { return .none }
                state.autoSaveSeconds = seconds - 1
                return seconds == 1 ? .send(.saveTapped) : .none

            case .saveTapped:
                guard state.phase == .review, let id = state.recordID else { return .none }
                state.phase = .saving
                return settle(state.experimentID, recordID: id, operation: .confirmRecord)

            case let .saveResponse(id, response):
                guard state.recordID == id, state.phase == .saving else { return .none }
                if let record = response?.record, record.phase == .saved {
                    return .send(.recordReceived(record))
                }
                state.phase = .review
                state.autoSaveSeconds = nil
                return .none

            case .retryTapped:
                guard state.phase == .failed, !state.shouldDismiss else { return .none }
                return start(uuid(), resume: false, state: &state)

            case .retakeTapped:
                guard state.phase == .review, let id = state.recordID else { return .none }
                state.phaseBeforeClose = state.phase
                state.phase = .closing
                return settle(
                    state.experimentID, recordID: id, operation: .cancelRecord, retake: true
                )

            case .closeTapped:
                guard state.phase != .closing, state.phase != .saving else { return .none }
                guard state.phase != .saved, state.phase != .failed, let id = state.recordID else {
                    state.shouldDismiss = true
                    return .none
                }
                state.phaseBeforeClose = state.phase
                state.phase = .closing
                return settle(state.experimentID, recordID: id, operation: .cancelRecord)

            case let .cancelFinished(id, retake, response):
                guard state.phase == .closing, state.recordID == id else { return .none }
                if response?.phase == .completed, response?.record?.phase == .cancelled {
                    client.clearPendingCameraRecord(
                        experimentID: state.experimentID, kind: .photo, recordID: id
                    )
                    if retake { return start(uuid(), resume: false, state: &state) }
                    state.shouldDismiss = true
                } else if let record = response?.record, record.phase == .saved {
                    return .send(.recordReceived(record))
                } else if !retake, state.phaseBeforeClose == .recovering {
                    state.shouldDismiss = true
                } else {
                    state.phase = state.phaseBeforeClose ?? .recovering
                    state.autoSaveSeconds = nil
                }
                return .none

            case .presentationEnded:
                state.shouldDismiss = true
                state.recordID = nil
                return .merge(
                    .cancel(id: CancelID.screens(presentationID)),
                    .cancel(id: CancelID.records(presentationID)),
                    .cancel(id: CancelID.autoSave(presentationID)),
                    .cancel(id: CancelID.capture(presentationID)),
                    .cancel(id: CancelID.settle(presentationID)),
                    .cancel(id: CancelID.captureWait(presentationID))
                )
            }
        }
    }
}

private extension PhotoRecordFeature {
    func start(_ id: UUID, resume: Bool, state: inout State) -> Effect<Action> {
        state.recordID = id
        state.recordRevision = nil
        state.phase = resume ? .recovering : .capturing
        state.autoSaveSeconds = 3
        let experimentID = state.experimentID
        let capture: Effect<Action> = .run { send in
            if !resume {
                do {
                    let response = try await client.startCameraRecord(
                        experimentID: experimentID, recordID: id, kind: .photo
                    )
                    await send(.captureResponse(id, response))
                } catch {
                    guard !Task.isCancelled else { return }
                    await send(.captureResponse(id, .init(requestID: id, phase: .failed)))
                }
            }
            for await response in await client.cameraRecordUpdates(
                experimentID: experimentID, recordID: id, kind: .photo
            ) {
                await send(.captureResponse(id, response))
            }
        }
        .cancellable(id: CancelID.capture(presentationID), cancelInFlight: true)
        return .merge(
            capture,
            .run { send in
                try await Task.sleep(for: .seconds(15))
                await send(.captureWaitElapsed(id))
            }
            .cancellable(id: CancelID.captureWait(presentationID), cancelInFlight: true)
        )
    }

    func failCapture(state: inout State, recordID: UUID) -> Effect<Action> {
        client.clearPendingCameraRecord(
            experimentID: state.experimentID, kind: .photo, recordID: recordID
        )
        state.phase = .failed
        return .merge(
            .cancel(id: CancelID.capture(presentationID)),
            .cancel(id: CancelID.autoSave(presentationID))
        )
    }

    func applyRecord(_ record: WatchRecordSnapshot, state: inout State) -> Effect<Action> {
        switch record.phase {
        case .review:
            if state.phase == .closing {
                state.phaseBeforeClose = .review
                return .none
            }
            guard state.phase == .capturing || state.phase == .recovering else { return .none }
            state.phase = .review
            guard record.canAutoSave != false else {
                state.autoSaveSeconds = nil
                return .none
            }
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
            if record.originalRetained == false {
                return failCapture(state: &state, recordID: record.id)
            }
            if state.phase != .closing {
                state.phase = record.originalRetained == true ? .review : .recovering
                state.autoSaveSeconds = nil
            }
            return .cancel(id: CancelID.autoSave(presentationID))
        default:
            break
        }
        return .none
    }

    func finishRecord(
        _ record: WatchRecordSnapshot, state: inout State
    ) -> Effect<Action> {
        client.clearPendingCameraRecord(
            experimentID: state.experimentID, kind: .photo, recordID: record.id
        )
        if record.phase == .saved {
            state.phase = .saved
        } else if state.phase != .closing {
            state.shouldDismiss = true
        }
        return .merge(
            .cancel(id: CancelID.capture(presentationID)),
            .cancel(id: CancelID.autoSave(presentationID))
        )
    }

    func settle(
        _ experimentID: UUID, recordID: UUID, operation: WatchExperimentCommand.Operation,
        retake: Bool = false
    ) -> Effect<Action> {
        .merge(
            .cancel(id: CancelID.autoSave(presentationID)),
            .run { send in
                let response = try? await client.finishCameraRecord(
                    experimentID: experimentID, recordID: recordID, kind: .photo,
                    operation: operation
                )
                if operation == .confirmRecord {
                    await send(.saveResponse(recordID, response))
                } else {
                    await send(.cancelFinished(recordID, retake: retake, response))
                }
            }
            .cancellable(id: CancelID.settle(presentationID), cancelInFlight: true)
        )
    }
}

private extension PhotoRecordFeature.State {
    mutating func receiveScreen(_ screen: WatchScreenSnapshot) {
        guard !shouldDismiss, screen.isValid else { return }
        if let previous = phoneScreen {
            if previous.epoch == screen.epoch {
                guard screen.revision > previous.revision else { return }
            } else if let previousEpoch = previous.epoch {
                guard screen.epoch?.isNewer(than: previousEpoch) == true else { return }
            }
        }
        phoneScreen = screen
    }
}
