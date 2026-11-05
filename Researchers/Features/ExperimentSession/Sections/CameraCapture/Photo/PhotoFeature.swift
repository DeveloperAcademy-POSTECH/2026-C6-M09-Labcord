import ComposableArchitecture
import Foundation
import LabcordiOS

@Reducer
struct PhotoFeature {
    @ObservableState
    struct State: Equatable {
        var isScheduled = false
        var scheduledAt: Date?
        var isCapturing = false
        var capturedData: Data?
        var isGestureArmed = false
        var errorMessage: String?
        let experimentID: UUID
        var recordID: UUID?
        var recordedAt: Date?
        var isSaving = false
        var isSessionClosing = false
        var saveError: String?
        var requestedRecordID: UUID?
        var pendingWatchCaptureID: UUID?
        var requiresExternalConfirmation = false
    }

    enum Action: Equatable {
        case gestureEvent(CameraHandEvent)
        case disarmGesture
        case cancelGesture
        case delayElapsed(UUID)
        case captureRequested(UUID?)
        case watchCaptureRequested(UUID)
        case shortcutCaptureRequested(UUID)
        case captured(UUID, Data)
        case captureFailed(String)
        case retakeRequested
        case saveRequested
        case autoSaveElapsed(UUID)
        case saved(UUID)
        case saveFailed(UUID, String)
        case saveErrorDismissed
        case errorDismissed
        case delegate(Delegate)
    }

    enum Delegate: Equatable {
        case captureRequested(UUID)
        case captureScheduled(UUID, Date)
    }

    private nonisolated enum CancelID: Hashable, Sendable {
        case captureDelay
        case autoSave
    }

    @Dependency(\.cameraSessionClient) var cameraSessionClient
    @Dependency(\.experimentClient) var experimentClient
    @Dependency(\.date.now) var now
    @Dependency(\.uuid) var uuid

    private func cancelScheduledCapture(in state: inout State) -> Effect<Action> {
        state.isScheduled = false
        state.scheduledAt = nil
        return .cancel(id: CancelID.captureDelay)
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            if state.isSessionClosing, action.isBlockedDuringSessionClose { return .none }
            switch action {
            case let .shortcutCaptureRequested(id):
                guard !state.isCapturing, !state.isScheduled,
                      state.capturedData == nil, !state.requiresExternalConfirmation else {
                    return .none
                }
                state.requestedRecordID = id
                state.isScheduled = true
                state.scheduledAt = now
                return .run { send in
                    try await Task.sleep(for: .seconds(5))
                    await send(.delayElapsed(id))
                }
                .cancellable(id: CancelID.captureDelay, cancelInFlight: true)

            case let .watchCaptureRequested(id):
                guard state.pendingWatchCaptureID == id,
                      !state.isCapturing, !state.isScheduled,
                      state.capturedData == nil else { return .none }
                state.pendingWatchCaptureID = nil
                state.requestedRecordID = id
                state.requiresExternalConfirmation = true
                state.isScheduled = true
                let scheduledAt = now
                state.scheduledAt = scheduledAt
                let delay = Effect<Action>.run { send in
                    try await Task.sleep(for: .seconds(5))
                    await send(.delayElapsed(id))
                }
                .cancellable(id: CancelID.captureDelay, cancelInFlight: true)
                return .merge(delay, .send(.delegate(.captureScheduled(id, scheduledAt))))

            case let .gestureEvent(.openHandHeld(detectedAt)):
                guard !state.isScheduled, !state.isCapturing,
                      state.capturedData == nil,
                      detectedAt.timeIntervalSinceNow > -0.5 else { return .none }
                state.isGestureArmed = true
                return .none

            case let .gestureEvent(.fistHeld(detectedAt)):
                let wasArmed = state.isGestureArmed
                state.isGestureArmed = false
                guard !state.isScheduled, !state.isCapturing,
                      state.capturedData == nil, wasArmed,
                      detectedAt.timeIntervalSinceNow > -0.5 else { return .none }
                let id = uuid()
                state.requestedRecordID = id
                state.isScheduled = true
                state.scheduledAt = now
                return .run { send in
                    try await Task.sleep(for: .seconds(5))
                    await send(.delayElapsed(id))
                }
                .cancellable(id: CancelID.captureDelay, cancelInFlight: true)

            case .gestureEvent:
                return .none

            case .disarmGesture:
                state.isGestureArmed = false
                return .none

            case .cancelGesture:
                state.pendingWatchCaptureID = nil
                state.isGestureArmed = false
                if !state.isCapturing, state.capturedData == nil {
                    state.requestedRecordID = nil
                    state.requiresExternalConfirmation = false
                }
                return cancelScheduledCapture(in: &state)

            case let .delayElapsed(id):
                guard state.isScheduled, state.requestedRecordID == id else { return .none }
                return .send(.delegate(.captureRequested(id)))

            case let .captureRequested(scheduledID):
                guard !state.isCapturing, state.capturedData == nil else { return .none }
                if let scheduledID {
                    guard state.isScheduled, state.requestedRecordID == scheduledID else {
                        return .none
                    }
                } else {
                    guard !state.isScheduled, !state.requiresExternalConfirmation else {
                        return .none
                    }
                }
                let cancelDelay = cancelScheduledCapture(in: &state)
                state.isCapturing = true
                let id = state.requestedRecordID ?? uuid()
                state.requestedRecordID = id
                return .merge(
                    cancelDelay,
                    .run { send in
                        do {
                            let data = try await cameraSessionClient.capturePhoto()
                            await send(.captured(id, data))
                        } catch {
                            await send(.captureFailed(error.localizedDescription))
                        }
                    }
                )

            case let .captured(id, data):
                guard state.requestedRecordID == id else { return .none }
                state.isCapturing = false
                state.capturedData = data
                state.recordID = id
                state.recordedAt = now
                state.saveError = nil
                if state.requiresExternalConfirmation { return .none }
                return .run { send in
                    try await Task.sleep(for: .seconds(3))
                    await send(.autoSaveElapsed(id))
                }
                .cancellable(id: CancelID.autoSave, cancelInFlight: true)

            case let .captureFailed(message):
                state.isCapturing = false
                state.requestedRecordID = nil
                state.requiresExternalConfirmation = false
                state.errorMessage = message
                return .none

            case .retakeRequested:
                guard !state.isSaving else { return .none }
                state.pendingWatchCaptureID = nil
                state.requestedRecordID = nil
                state.requiresExternalConfirmation = false
                state.capturedData = nil
                state.recordID = nil
                state.recordedAt = nil
                state.saveError = nil
                return .merge(
                    cancelScheduledCapture(in: &state),
                    .cancel(id: CancelID.autoSave)
                )

            case .saveRequested:
                return savePhoto(state: &state)

            case let .autoSaveElapsed(id):
                guard state.recordID == id else { return .none }
                return savePhoto(state: &state)

            case let .saved(id):
                guard state.recordID == id else { return .none }
                state.requestedRecordID = nil
                state.isSaving = false
                state.capturedData = nil
                state.recordID = nil
                state.recordedAt = nil
                state.saveError = nil
                state.requiresExternalConfirmation = false
                return .none

            case let .saveFailed(id, message):
                guard state.recordID == id else { return .none }
                state.isSaving = false
                state.saveError = message
                return .none

            case .saveErrorDismissed:
                state.saveError = nil
                return .none

            case .errorDismissed:
                state.errorMessage = nil
                return .none

            case .delegate:
                return .none
            }
        }
    }

    private func savePhoto(state: inout State) -> Effect<Action> {
        guard let id = state.recordID,
              let recordedAt = state.recordedAt,
              let data = state.capturedData,
              !state.isSaving else { return .none }
        state.isSaving = true
        state.saveError = nil
        let experimentID = state.experimentID
        return .concatenate(
            .cancel(id: CancelID.autoSave),
            .run { send in
                do {
                    try await experimentClient.savePhoto(experimentID, id, recordedAt, data)
                    await send(.saved(id))
                } catch {
                    await send(.saveFailed(id, error.localizedDescription))
                }
            }
        )
    }
}

private extension PhotoFeature.Action {
    var isBlockedDuringSessionClose: Bool {
        switch self {
        case .watchCaptureRequested, .shortcutCaptureRequested, .gestureEvent,
             .captureRequested, .retakeRequested: true
        default: false
        }
    }
}
