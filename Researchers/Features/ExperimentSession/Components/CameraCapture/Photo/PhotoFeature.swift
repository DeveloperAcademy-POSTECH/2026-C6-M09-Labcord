import ComposableArchitecture
import Foundation
import LabcordiOS
import LabcordShared

@Reducer
struct PhotoFeature {
    @ObservableState
    struct State: Equatable {
        @SharedReader(.suppressPhotoShutterSound) var suppressPhotoShutterSound = false
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
        var autoSaveEndsAt: Date?
        var lastSavedRecordID: UUID?
        var countdownEndAt: Date?
        var requestedRecordID: UUID?
        var pendingWatchCaptureID: UUID?
        var isWatchCapture = false

        var watchCaptureID: UUID? {
            pendingWatchCaptureID ?? (isWatchCapture ? requestedRecordID : nil)
        }
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
        case captureFailed(UUID, String, error: WatchExperimentError = .cameraUnavailable)
        case retakeRequested
        case discardHiddenLocalCapture(UUID)
        case watchCancelRequested(UUID)
        case watchSaveRequested(UUID)
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
        state.countdownEndAt = nil
        state.scheduledAt = nil
        return .cancel(id: CancelID.captureDelay)
    }

    private func scheduleCapture(
        id: UUID,
        at scheduledAt: Date,
        in state: inout State
    ) -> Effect<Action> {
        state.requestedRecordID = id
        state.isScheduled = true
        state.scheduledAt = scheduledAt
        state.countdownEndAt = scheduledAt.addingTimeInterval(5)
        return .run { send in
            try await Task.sleep(for: .seconds(5))
            await send(.delayElapsed(id))
        }
        .cancellable(id: CancelID.captureDelay, cancelInFlight: true)
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            if state.isSessionClosing, action.isBlockedDuringSessionClose { return .none }
            switch action {
            case let .shortcutCaptureRequested(id):
                guard !state.isCapturing, !state.isScheduled,
                      state.capturedData == nil, state.watchCaptureID == nil else {
                    return .none
                }
                return scheduleCapture(id: id, at: now, in: &state)

            case let .watchCaptureRequested(id):
                guard state.pendingWatchCaptureID == id else { return .none }
                state.pendingWatchCaptureID = nil
                guard !state.isCapturing, !state.isScheduled,
                      state.capturedData == nil else { return .none }
                state.isGestureArmed = false
                state.isWatchCapture = true
                return scheduleCapture(id: id, at: now, in: &state)

            case let .gestureEvent(.openHandHeld(detectedAt)):
                guard !state.isScheduled, !state.isCapturing,
                      state.capturedData == nil, state.watchCaptureID == nil,
                      detectedAt.timeIntervalSinceNow > -0.5 else { return .none }
                state.isGestureArmed = true
                return .none

            case let .gestureEvent(.fistHeld(detectedAt)):
                let wasArmed = state.isGestureArmed
                state.isGestureArmed = false
                guard !state.isScheduled, !state.isCapturing,
                      state.capturedData == nil, state.watchCaptureID == nil, wasArmed,
                      detectedAt.timeIntervalSinceNow > -0.5 else { return .none }
                return scheduleCapture(id: uuid(), at: now, in: &state)

            case .gestureEvent:
                return .none

            case .disarmGesture:
                state.isGestureArmed = false
                return .none

            case .cancelGesture:
                state.isGestureArmed = false
                guard state.watchCaptureID == nil else { return .none }
                if !state.isCapturing, state.capturedData == nil {
                    state.requestedRecordID = nil
                    state.isWatchCapture = false
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
                    guard !state.isScheduled, state.watchCaptureID == nil else {
                        return .none
                    }
                }
                let cancelDelay = cancelScheduledCapture(in: &state)
                state.isCapturing = true
                let id = state.requestedRecordID ?? uuid()
                state.requestedRecordID = id
                let suppressShutterSound = state.suppressPhotoShutterSound
                return .merge(
                    cancelDelay,
                    .run { send in
                        do {
                            let data = try await cameraSessionClient.capturePhoto(
                                suppressShutterSound
                            )
                            await send(.captured(id, data))
                        } catch let error as PermissionAccessError {
                            await send(.captureFailed(
                                id, error.localizedDescription, error: .permissionDenied
                            ))
                        } catch {
                            await send(.captureFailed(id, error.localizedDescription))
                        }
                    }
                )

            case let .captured(id, data):
                guard state.isCapturing, state.requestedRecordID == id else { return .none }
                state.isCapturing = false
                state.capturedData = data
                state.recordID = id
                let capturedAt = now
                state.recordedAt = capturedAt
                state.autoSaveEndsAt = capturedAt.addingTimeInterval(3)
                state.saveError = nil
                return .run { send in
                    try await Task.sleep(for: .seconds(3))
                    await send(.autoSaveElapsed(id))
                }
                .cancellable(id: CancelID.autoSave, cancelInFlight: true)

            case let .captureFailed(id, message, _):
                guard state.requestedRecordID == id, state.capturedData == nil,
                      state.isScheduled || state.isCapturing else { return .none }
                state.isCapturing = false
                state.requestedRecordID = nil
                state.isWatchCapture = false
                state.errorMessage = message
                return cancelScheduledCapture(in: &state)

            case .retakeRequested:
                guard !state.isSaving, !state.isCapturing else { return .none }
                return resetPhoto(in: &state)

            case let .discardHiddenLocalCapture(id):
                guard state.recordID == id, state.watchCaptureID == nil,
                      !state.isSaving else { return .none }
                return resetPhoto(in: &state)

            case let .watchCancelRequested(id):
                guard !state.isSaving, !state.isCapturing,
                      state.requestedRecordID == id || state.recordID == id else {
                    return .none
                }
                return resetPhoto(in: &state)

            case let .watchSaveRequested(id):
                guard state.recordID == id, state.isWatchCapture else {
                    return .none
                }
                return savePhoto(state: &state)

            case .saveRequested:
                return savePhoto(state: &state)

            case let .autoSaveElapsed(id):
                guard state.recordID == id, state.autoSaveEndsAt != nil else { return .none }
                return savePhoto(state: &state)

            case let .saved(id):
                guard state.recordID == id else { return .none }
                state.lastSavedRecordID = id
                state.requestedRecordID = nil
                state.isSaving = false
                state.capturedData = nil
                state.recordID = nil
                state.recordedAt = nil
                state.saveError = nil
                state.isWatchCapture = false
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
}

private extension PhotoFeature {
    func resetPhoto(in state: inout State) -> Effect<Action> {
        state.pendingWatchCaptureID = nil
        state.requestedRecordID = nil
        state.isWatchCapture = false
        state.capturedData = nil
        state.autoSaveEndsAt = nil
        state.recordID = nil
        state.recordedAt = nil
        state.saveError = nil
        return .merge(
            cancelScheduledCapture(in: &state),
            .cancel(id: CancelID.autoSave)
        )
    }

    func savePhoto(state: inout State) -> Effect<Action> {
        guard let id = state.recordID,
              let recordedAt = state.recordedAt,
              let data = state.capturedData,
              !state.isSaving else { return .none }
        state.isSaving = true
        state.autoSaveEndsAt = nil
        state.saveError = nil
        let experimentID = state.experimentID
        return .run { send in
            do {
                try await experimentClient.savePhoto(experimentID, id, recordedAt, data)
                await send(.saved(id))
            } catch {
                await send(.saveFailed(id, error.localizedDescription))
            }
        }
    }
}

private extension PhotoFeature.Action {
    var isBlockedDuringSessionClose: Bool {
        switch self {
        case .watchCaptureRequested, .shortcutCaptureRequested, .gestureEvent,
             .captureRequested, .retakeRequested, .discardHiddenLocalCapture: true
        default: false
        }
    }
}
