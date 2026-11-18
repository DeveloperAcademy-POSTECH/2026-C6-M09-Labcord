import ComposableArchitecture
import Foundation
import LabcordShared
import LabcordWatchOS
import OSLog

private let watchPhotoCancelLog = Logger(
    subsystem: "com.researchers.Researchers.watchkitapp", category: "WatchPhotoCancel"
)

@Reducer
struct PhotoRecordFeature {
    enum Phase: Equatable {
        case capturing, captureFailed, review, saving, saved, closing, cancelFailed
    }

    @ObservableState
    struct State: Equatable {
        let experimentID: UUID
        var recordID: UUID?
        var phase: Phase = .capturing
        var requests = WatchCameraRequests()
        var cancellation: WatchCameraCancellation?
        var autoSaveSeconds: Int? = 3
        var shouldDismiss = false
    }

    enum Action {
        case appeared, disappeared, retryTapped, recordReceived(WatchRecordSnapshot)
        case requestEvent(UUID, WatchCameraRequestEvent)
        case saveTapped, retakeTapped, closeTapped, autoSaveTick(UUID)
    }

    private nonisolated enum CancelID: Hashable, Sendable {
        case records, autoSave, request
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
                let canCheck = state.phase == .capturing
                    && !state.requests.isWaiting(for: .takePhoto)
                guard state.phase == .captureFailed || canCheck else { return .none }
                if state.requests.lastRecord?.originalRetained == false,
                   state.requests.lastRecord?.phase == .failed { return start(&state) }
                state.phase = .capturing
                return request(.takePhoto, state: &state)

            case let .requestEvent(id, event):
                guard let operation = state.requests.receive(event, from: id) else { return .none }
                switch event {
                case .prepared, .rejected: return .none
                case let .received(record): return .send(.recordReceived(record))
                case .failed:
                    if operation == .cancelRecord, state.phase == .closing {
                        state.phase = .cancelFailed
                    } else if operation == .confirmRecord, state.phase == .saving {
                        state.phase = .review
                        state.autoSaveSeconds = nil
                    } else if operation == .takePhoto, state.phase == .capturing {
                        state.phase = .captureFailed
                    }
                    return .none
                }

            case let .recordReceived(record):
                return receive(record, state: &state)

            case let .autoSaveTick(id):
                guard state.recordID == id, state.phase == .review,
                      let seconds = state.autoSaveSeconds else { return .none }
                state.autoSaveSeconds = seconds - 1
                return seconds == 1 ? .send(.saveTapped) : .none

            case .saveTapped:
                let canRetry = state.phase == .saving
                    && !state.requests.isWaiting(for: .confirmRecord)
                guard state.phase == .review || canRetry else { return .none }
                state.phase = .saving
                return .merge(
                    .cancel(id: CancelID.autoSave), request(.confirmRecord, state: &state)
                )

            case .retakeTapped:
                guard state.phase == .review else { return .none }
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

private extension PhotoRecordFeature {
    func start(_ state: inout State) -> Effect<Action> {
        state.recordID = uuid()
        state.phase = .capturing
        state.requests = WatchCameraRequests()
        state.cancellation = nil
        state.autoSaveSeconds = nil
        return request(.takePhoto, state: &state)
    }

    func cancel(_ state: inout State) -> Effect<Action> {
        state.phase = .closing
        state.autoSaveSeconds = nil
        watchPhotoCancelLog.info("sending photo cancellation")
        return .merge(.cancel(id: CancelID.autoSave), request(.cancelRecord, state: &state))
    }

    func request(
        _ operation: WatchExperimentCommand.Operation, state: inout State
    ) -> Effect<Action> {
        guard let recordID = state.recordID else { return .none }
        let attempt = state.requests.begin(
            operation, id: uuid(), experimentID: state.experimentID,
            recordID: recordID, kind: .photo
        )
        return .run { send in
            await attempt.run(using: client) { await send(.requestEvent(attempt.id, $0)) }
        }
        .cancellable(id: CancelID.request, cancelInFlight: true)
    }

    func receive(_ record: WatchRecordSnapshot, state: inout State) -> Effect<Action> {
        guard !state.shouldDismiss, record.kind == .photo, record.id == state.recordID,
              record.experimentID == state.experimentID, state.requests.accept(record)
        else { return .none }
        switch record.phase {
        case .cancelled:
            if state.cancellation == .retake { return start(&state) }
            state.shouldDismiss = true
        case .saved:
            state.phase = .saved
        case .capturing where state.phase == .captureFailed:
            state.phase = .capturing
            return .none
        case .review, .previewing:
            return review(record, state: &state)
        case .saving:
            guard state.cancellation == nil else { return .none }
            state.phase = .saving
        case .failed:
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
        return record.originalRetained == true ? .review : .captureFailed
    }

    func review(_ record: WatchRecordSnapshot, state: inout State) -> Effect<Action> {
        guard state.cancellation == nil, [.capturing, .captureFailed].contains(state.phase)
        else { return .none }
        state.phase = .review
        state.autoSaveSeconds = record.canAutoSave == false ? nil : 3
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
