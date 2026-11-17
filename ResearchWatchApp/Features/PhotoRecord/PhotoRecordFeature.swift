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
        case capturing, review, saving, saved, closing
    }

    @ObservableState
    struct State: Equatable {
        let experimentID: UUID
        var recordID: UUID?
        var phase: Phase = .capturing
        var autoSaveSeconds: Int? = 3
        var shouldDismiss = false
    }

    enum Action {
        case appeared, disappeared, recordReceived(WatchRecordSnapshot)
        case captureResponse(UUID, WatchExperimentResponse?)
        case saveTapped, saveResponse(UUID, WatchExperimentResponse?)
        case retakeTapped, retakeFinished(UUID)
        case closeTapped, closeFinished(Bool), autoSaveTick(UUID)
    }

    private nonisolated enum CancelID: Hashable, Sendable {
        case records, autoSave, capture
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
                    .send(.retakeFinished(uuid()))
                )

            case let .retakeFinished(id):
                guard !state.shouldDismiss, state.phase != .closing else { return .none }
                state.recordID = id
                state.phase = .capturing
                state.autoSaveSeconds = 3
                let experimentID = state.experimentID
                return .run { send in
                    let response = try? await client.takePhoto(
                        experimentID: experimentID, recordID: id
                    )
                    await send(.captureResponse(id, response))
                }
                .cancellable(id: CancelID.capture, cancelInFlight: true)

            case let .captureResponse(id, response):
                guard state.recordID == id else { return .none }
                if let record = response?.record { return .send(.recordReceived(record)) }
                return .none

            case let .recordReceived(record):
                guard record.experimentID == state.experimentID,
                      record.id == state.recordID, record.kind == .photo,
                      !state.shouldDismiss else { return .none }
                switch record.phase {
                case .review:
                    guard state.phase == .capturing else { return .none }
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
                    state.shouldDismiss = true
                    return .cancel(id: CancelID.autoSave)
                default:
                    return .none
                }

            case let .autoSaveTick(id):
                guard state.recordID == id, state.phase == .review else { return .none }
                guard let seconds = state.autoSaveSeconds else { return .none }
                state.autoSaveSeconds = seconds - 1
                return seconds == 1 ? .send(.saveTapped) : .none

            case .saveTapped:
                guard state.phase == .review, let id = state.recordID else { return .none }
                state.phase = .saving
                let experimentID = state.experimentID
                return .merge(
                    .cancel(id: CancelID.autoSave),
                    .run { send in
                        let response = try? await client.finishPhoto(
                            experimentID: experimentID, recordID: id, operation: .confirmRecord
                        )
                        await send(.saveResponse(id, response))
                    }
                )

            case let .saveResponse(id, response):
                guard state.recordID == id else { return .none }
                if let record = response?.record { return .send(.recordReceived(record)) }
                return .none

            case .retakeTapped:
                guard state.phase == .review, let id = state.recordID else { return .none }
                state.phase = .capturing
                let experimentID = state.experimentID
                let nextID = uuid()
                state.recordID = nextID
                return .merge(
                    .cancel(id: CancelID.autoSave),
                    .run { send in
                        _ = await client.cancelPhoto(experimentID: experimentID, recordID: id)
                        await send(.retakeFinished(nextID))
                    }
                )

            case .closeTapped:
                guard state.phase != .closing else { return .none }
                guard state.phase != .saved, let id = state.recordID else {
                    watchPhotoCancelLog.info("closed without request")
                    state.shouldDismiss = true
                    return .none
                }
                watchPhotoCancelLog.info("sending \(id.uuidString, privacy: .public)")
                state.phase = .closing
                let experimentID = state.experimentID
                return .merge(
                    .cancel(id: CancelID.capture),
                    .cancel(id: CancelID.autoSave),
                    .run { send in
                        let cancelled = await client.cancelPhoto(
                            experimentID: experimentID, recordID: id
                        )
                        await send(.closeFinished(cancelled))
                    }
                )

            case let .closeFinished(cancelled):
                guard state.phase == .closing else { return .none }
                watchPhotoCancelLog.info("completed \(cancelled)")
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
                    .cancel(id: CancelID.autoSave),
                    .cancel(id: CancelID.capture)
                )
            }
        }
    }
}

private extension WatchExperimentClient {
    func takePhoto(experimentID: UUID, recordID: UUID) async throws
        -> WatchExperimentResponse {
        let current = try await photoSnapshot(experimentID)
        let preparation = try await sendAndWait(WatchExperimentCommand(
            operation: .prepareStart, experimentID: experimentID,
            expectedRevision: current.revision
        ))
        guard let token = preparation.startToken else {
            throw WatchExperimentError.resultUnknown
        }
        try Task.checkCancellation()
        return try await sendAndWait(WatchExperimentCommand(
            requestID: recordID, operation: .takePhoto, experimentID: experimentID,
            expectedRevision: preparation.snapshot?.revision ?? current.revision,
            targetID: recordID, startToken: token
        ), returnWhenCapturing: true)
    }

    func finishPhoto(
        experimentID: UUID, recordID: UUID, operation: WatchExperimentCommand.Operation
    ) async throws -> WatchExperimentResponse {
        let current = try await photoSnapshot(experimentID)
        return try await sendAndWait(WatchExperimentCommand(
            operation: operation, experimentID: experimentID,
            expectedRevision: current.revision, targetID: recordID
        ))
    }

    func cancelPhoto(experimentID: UUID, recordID: UUID) async -> Bool {
        let immediate = WatchExperimentCommand(
            operation: .cancelRecord, experimentID: experimentID, targetID: recordID
        )
        do {
            let response = try await sendAndWait(immediate)
            if response.phase == .completed { return true }
        } catch {
            watchPhotoCancelLog.error("immediate failed \(String(describing: error))")
        }
        for _ in 0..<20 {
            if let response = try? await finishPhoto(
                experimentID: experimentID, recordID: recordID, operation: .cancelRecord
            ), response.phase == .completed { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    func photoSnapshot(_ experimentID: UUID) async throws -> WatchExperimentSnapshot {
        let response = try await send(WatchExperimentCommand(
            operation: .snapshot, experimentID: experimentID
        ))
        guard response.phase == .completed, let snapshot = response.snapshot else {
            throw response.error ?? WatchExperimentError.resultUnknown
        }
        return snapshot
    }

    func sendAndWait(
        _ command: WatchExperimentCommand, returnWhenCapturing: Bool = false
    ) async throws -> WatchExperimentResponse {
        var response = try await send(command)
        for _ in 0..<30 {
            if response.phase == .failed || response.phase == .unknown {
                throw response.error ?? WatchExperimentError.resultUnknown
            }
            if response.phase == .completed || returnWhenCapturing
                && response.record?.phase == .capturing { return response }
            try await Task.sleep(for: .milliseconds(100))
            response = try await send(WatchExperimentCommand(
                operation: .requestStatus, targetID: command.requestID
            ))
        }
        throw WatchExperimentError.deliveryTimeout
    }
}
