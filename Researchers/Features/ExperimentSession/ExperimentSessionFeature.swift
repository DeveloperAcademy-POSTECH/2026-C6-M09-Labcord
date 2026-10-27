import ComposableArchitecture
import Foundation
import LabcordiOS
import LabcordShared

@Reducer
struct ExperimentSessionFeature {
    enum TimerTab: Equatable {
        case configured
        case active
    }

    @ObservableState
    struct State: Equatable {
        var permissions = SessionPermissionsFeature.State()
        var cameraOwnerID = UUID()
        var isCameraViewVisible = false
        var cameraErrorMessage: String?
        var previewConnector: CameraPreviewConnector?
        var isCameraSwitching = false
        var isPhotoCaptureScheduled = false
        var isCapturingPhoto = false
        var capturedPhotoData: Data?
        var selectedTimerTab: TimerTab = .configured
        var timerSeconds: [Int]
        var mode: ExperimentMode
        var timerCollection = ExperimentTimerCollection()

        init(timerSeconds: [Int] = [5400, 120, 10, 5, 120, 30, 60, 900, 2000, 2500, 3000, 150]) {
            self.timerSeconds = timerSeconds
            self.mode = timerSeconds.isEmpty ? .free : .procedure
        }
    }

    enum Action: Equatable {
        case timerTabSelected(TimerTab)
        case timerStarted(Int)
        case customTimerStarted(Int)
        case timerPaused(UUID)
        case timerResumed(UUID)
        case timerDeleted(UUID)
        case timerTick(Date)
        case cameraViewAppeared
        case cameraViewDisappeared
        case permissions(SessionPermissionsFeature.Action)
        case cameraStarted(UUID, CameraPreviewConnector)
        case cameraSwitchRequested
        case cameraSwitched(CameraPreviewConnector)
        case cameraStartFailed(UUID, String)
        case cameraSwitchFailed(String)
        case cameraErrorDismissed
        case handEvent(CameraHandEvent)
        case photoCaptureDelayElapsed
        case photoCaptureRequested
        case photoCaptured(Data)
        case photoCaptureFailed(String)
        case retakeRequested
    }

    private nonisolated enum CancelID: Hashable, Sendable {
        case timerTick
        case handTracking
        case photoCaptureDelay
    }

    private var tickerEffect: Effect<Action> {
        .run { send in
            while !Task.isCancelled {
                try await Task.sleep(for: .seconds(1))
                await send(.timerTick(.now))
            }
        }
        .cancellable(id: CancelID.timerTick, cancelInFlight: true)
    }

    private func cancelScheduledPhoto(in state: inout State) -> Effect<Action> {
        state.isPhotoCaptureScheduled = false
        return .cancel(id: CancelID.photoCaptureDelay)
    }

    @Dependency(\.cameraSessionClient) var cameraSessionClient

    var body: some Reducer<State, Action> {
        Scope(state: \.permissions, action: \.permissions) {
            SessionPermissionsFeature()
        }

        Reduce { state, action in
            switch action {
            case .cameraViewAppeared:
                guard !state.isCameraViewVisible else { return .none }
                state.isCameraViewVisible = true
                state.cameraOwnerID = UUID()
                return .none

            case .cameraViewDisappeared:
                guard state.isCameraViewVisible else { return .none }
                state.isCameraViewVisible = false
                let ownerID = state.cameraOwnerID
                return .merge(
                    .send(.permissions(.cancelRequest)),
                    .cancel(id: CancelID.handTracking),
                    cancelScheduledPhoto(in: &state),
                    .run { _ in await cameraSessionClient.deactivate(ownerID) }
                )

            case let .timerTabSelected(tab):
                state.selectedTimerTab = tab
                return .none

            case let .timerStarted(index):
                guard state.timerSeconds.indices.contains(index) else { return .none }

                let wasRunning = state.timerCollection.hasRunningTimers
                guard state.timerCollection.start(
                    durationSeconds: state.timerSeconds[index],
                    at: .now
                ) else { return .none }
                state.selectedTimerTab = .active
                return wasRunning ? .none : tickerEffect

            case let .customTimerStarted(seconds):
                let wasRunning = state.timerCollection.hasRunningTimers
                guard state.timerCollection.start(durationSeconds: seconds, at: .now) else {
                    return .none
                }
                state.selectedTimerTab = .active
                return wasRunning ? .none : tickerEffect

            case let .timerPaused(id):
                state.timerCollection.pause(id: id, at: .now)
                return state.timerCollection.hasRunningTimers
                    ? .none
                    : .cancel(id: CancelID.timerTick)

            case let .timerResumed(id):
                let wasRunning = state.timerCollection.hasRunningTimers
                guard state.timerCollection.resume(id: id, at: .now) else { return .none }
                return wasRunning ? .none : tickerEffect

            case let .timerDeleted(id):
                state.timerCollection.delete(id: id)
                return .none

            case let .timerTick(now):
                state.timerCollection.advance(to: now)
                return state.timerCollection.hasRunningTimers
                    ? .none
                    : .cancel(id: CancelID.timerTick)

            case .permissions(.camera(.statusUpdated(.authorized))):
                guard state.isCameraViewVisible else { return .none }
                let ownerID = state.cameraOwnerID
                return .run { send in
                    do {
                        try await cameraSessionClient.activate(ownerID)
                        let connector = await cameraSessionClient.previewConnector()
                        await send(.cameraStarted(ownerID, connector))
                    } catch let error as PermissionAccessError {
                        await send(.permissions(.accessFailed(error.kind)))
                    } catch {
                        await send(.cameraStartFailed(ownerID, error.localizedDescription))
                    }
                }

            case let .cameraStarted(ownerID, connector):
                guard state.isCameraViewVisible, ownerID == state.cameraOwnerID else {
                    return .run { _ in await cameraSessionClient.deactivate(ownerID) }
                }
                state.cameraErrorMessage = nil
                state.previewConnector = connector
                return .run { send in
                    for await event in await cameraSessionClient.handEvents() {
                        await send(.handEvent(event))
                    }
                }
                .cancellable(id: CancelID.handTracking, cancelInFlight: true)

            case .cameraSwitchRequested:
                guard state.previewConnector != nil, !state.isCameraSwitching,
                      !state.isCapturingPhoto, state.capturedPhotoData == nil else { return .none }
                state.isCameraSwitching = true
                return .merge(
                    cancelScheduledPhoto(in: &state),
                    .run { send in
                        do {
                            try await cameraSessionClient.switchCamera()
                            let connector = await cameraSessionClient.previewConnector()
                            await send(.cameraSwitched(connector))
                        } catch {
                            await send(.cameraSwitchFailed(error.localizedDescription))
                        }
                    }
                )

            case let .cameraSwitched(connector):
                state.isCameraSwitching = false
                state.cameraErrorMessage = nil
                state.previewConnector = connector
                return .none

            case let .cameraStartFailed(ownerID, message):
                guard state.isCameraViewVisible, ownerID == state.cameraOwnerID else { return .none }
                state.cameraErrorMessage = message
                return .none

            case let .cameraSwitchFailed(message):
                state.isCameraSwitching = false
                state.cameraErrorMessage = message
                return .none

            case .cameraErrorDismissed:
                state.cameraErrorMessage = nil
                return .none

            case let .handEvent(.fistHeld(detectedAt)):
                guard state.isCameraViewVisible, state.previewConnector != nil,
                      !state.isPhotoCaptureScheduled, !state.isCapturingPhoto,
                      !state.isCameraSwitching, state.capturedPhotoData == nil,
                      detectedAt.timeIntervalSinceNow > -0.5 else { return .none }
                state.isPhotoCaptureScheduled = true
                return .run { send in
                    try await Task.sleep(for: .seconds(5))
                    await send(.photoCaptureDelayElapsed)
                }
                .cancellable(id: CancelID.photoCaptureDelay, cancelInFlight: true)

            case .photoCaptureDelayElapsed:
                guard state.isPhotoCaptureScheduled else { return .none }
                state.isPhotoCaptureScheduled = false
                return .send(.photoCaptureRequested)

            case .photoCaptureRequested:
                guard state.isCameraViewVisible, state.previewConnector != nil,
                      !state.isCapturingPhoto,
                      state.capturedPhotoData == nil, !state.isCameraSwitching else { return .none }
                let cancelDelay = cancelScheduledPhoto(in: &state)
                state.isCapturingPhoto = true
                return .merge(
                    cancelDelay,
                    .run { send in
                        do {
                            await send(.photoCaptured(try await cameraSessionClient.capturePhoto()))
                        } catch {
                            await send(.photoCaptureFailed(error.localizedDescription))
                        }
                    }
                )

            case let .photoCaptured(data):
                state.isCapturingPhoto = false
                if state.isCameraViewVisible { state.capturedPhotoData = data }
                return .none

            case let .photoCaptureFailed(message):
                state.isCapturingPhoto = false
                state.cameraErrorMessage = message
                return .none

            case .retakeRequested:
                state.capturedPhotoData = nil
                return cancelScheduledPhoto(in: &state)

            case .permissions:
                return .none
            }
        }
    }
}
