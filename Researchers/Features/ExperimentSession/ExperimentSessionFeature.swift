import ComposableArchitecture
import Foundation
import LabcordiOS

@Reducer
struct ExperimentSessionFeature {
    enum TimerTab: Equatable {
        case configured
        case active
    }
    
    @ObservableState
    struct State: Equatable {
        var selectedTimerTab: TimerTab = .configured
        var cameraPermission = CameraPermssionFeature.State()
        var cameraErrorMessage: String?
        var previewConnector: CameraPreviewConnector?
        var isCameraSwitching = false
    }
    
    enum Action: Equatable {
        case timerTabSelected(TimerTab)
        case cameraPermission(CameraPermssionFeature.Action)
        case cameraStarted(CameraPreviewConnector)
        case cameraSwitchRequested
        case cameraSwitched(CameraPreviewConnector)
        case cameraStartFailed(String)
        case cameraErrorDismissed
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
