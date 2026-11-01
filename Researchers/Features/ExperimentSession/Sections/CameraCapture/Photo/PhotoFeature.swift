import ComposableArchitecture
import Foundation
import LabcordiOS

@Reducer
struct PhotoFeature {
    @ObservableState
    struct State: Equatable {
        var isScheduled = false
        var isCapturing = false
        var capturedData: Data?
        var isGestureArmed = false
        var errorMessage: String?
        let experimentID: UUID
        var recordID: UUID?
        var recordedAt: Date?
        var isSaving = false
        var saveError: String?
    }

    enum Action: Equatable {
        case gestureEvent(CameraHandEvent)
        case disarmGesture
        case cancelGesture
        case delayElapsed
        case captureRequested
        case captured(Data)
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
        case captureRequested
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
        return .cancel(id: CancelID.captureDelay)
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
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
                state.isScheduled = true
                return .run { send in
                    try await Task.sleep(for: .seconds(5))
                    await send(.delayElapsed)
                }
                .cancellable(id: CancelID.captureDelay, cancelInFlight: true)

            case .gestureEvent:
                return .none

            case .disarmGesture:
                state.isGestureArmed = false
                return .none

            case .cancelGesture:
                state.isGestureArmed = false
                return cancelScheduledCapture(in: &state)

            case .delayElapsed:
                guard state.isScheduled else { return .none }
                return .send(.delegate(.captureRequested))

            case .captureRequested:
                guard !state.isCapturing, state.capturedData == nil else { return .none }
                let cancelDelay = cancelScheduledCapture(in: &state)
                state.isCapturing = true
                return .merge(
                    cancelDelay,
                    .run { send in
                        do {
                            await send(.captured(try await cameraSessionClient.capturePhoto()))
                        } catch {
                            await send(.captureFailed(error.localizedDescription))
                        }
                    }
                )

            case let .captured(data):
                state.isCapturing = false
                state.capturedData = data
                let id = uuid()
                state.recordID = id
                state.recordedAt = now
                state.saveError = nil
                return .run { send in
                    try await Task.sleep(for: .seconds(3))
                    await send(.autoSaveElapsed(id))
                }
                .cancellable(id: CancelID.autoSave, cancelInFlight: true)

            case let .captureFailed(message):
                state.isCapturing = false
                state.errorMessage = message
                return .none

            case .retakeRequested:
                guard !state.isSaving else { return .none }
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
                state.isSaving = false
                state.capturedData = nil
                state.recordID = nil
                state.recordedAt = nil
                state.saveError = nil
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
