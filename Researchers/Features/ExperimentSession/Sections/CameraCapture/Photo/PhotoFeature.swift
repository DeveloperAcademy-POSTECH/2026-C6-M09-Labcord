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
        case errorDismissed
        case delegate(Delegate)
    }

    enum Delegate: Equatable {
        case captureRequested
    }

    private nonisolated enum CancelID: Hashable, Sendable {
        case captureDelay
    }

    @Dependency(\.cameraSessionClient) var cameraSessionClient

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
                return .none

            case let .captureFailed(message):
                state.isCapturing = false
                state.errorMessage = message
                return .none

            case .retakeRequested:
                state.capturedData = nil
                return cancelScheduledCapture(in: &state)

            case .errorDismissed:
                state.errorMessage = nil
                return .none

            case .delegate:
                return .none
            }
        }
    }
}
