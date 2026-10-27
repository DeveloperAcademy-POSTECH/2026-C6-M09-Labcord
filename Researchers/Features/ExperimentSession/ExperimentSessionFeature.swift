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
        var cameraPermission = CameraPermssionFeature.State()
        var cameraErrorMessage: String?
        var previewConnector: CameraPreviewConnector?
        var isCameraSwitching = false
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
        case cameraPermission(CameraPermssionFeature.Action)
        case cameraStarted(CameraPreviewConnector)
        case cameraSwitchRequested
        case cameraSwitched(CameraPreviewConnector)
        case cameraStartFailed(String)
        case cameraErrorDismissed
    }

    private nonisolated enum CancelID: Hashable, Sendable {
        case timerTick
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

    @Dependency(\.cameraSessionClient) var cameraSessionClient

    var body: some Reducer<State, Action> {
        Scope(state: \.cameraPermission, action: \.cameraPermission) {
            CameraPermssionFeature()
        }

        Reduce { state, action in
            switch action {
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

            case .cameraPermission(.statusUpdated(.authorized)):
                return .run { send in
                    do {
                        try await cameraSessionClient.start()
                        let connector = await cameraSessionClient.previewConnector()
                        await send(.cameraStarted(connector))
                    } catch {
                        await send(.cameraStartFailed(error.localizedDescription))
                    }
                }

            case let .cameraStarted(connector):
                state.cameraErrorMessage = nil
                state.previewConnector = connector
                return .none

            case .cameraSwitchRequested:
                guard state.previewConnector != nil, !state.isCameraSwitching else { return .none }
                state.isCameraSwitching = true
                return .run { send in
                    do {
                        try await cameraSessionClient.switchCamera()
                        let connector = await cameraSessionClient.previewConnector()
                        await send(.cameraSwitched(connector))
                    } catch {
                        await send(.cameraStartFailed(error.localizedDescription))
                    }
                }

            case let .cameraSwitched(connector):
                state.isCameraSwitching = false
                state.cameraErrorMessage = nil
                state.previewConnector = connector
                return .none

            case let .cameraStartFailed(message):
                state.isCameraSwitching = false
                state.cameraErrorMessage = message
                return .none

            case .cameraErrorDismissed:
                state.cameraErrorMessage = nil
                return .none

            case .cameraPermission:
                return .none
            }
        }
    }
}
