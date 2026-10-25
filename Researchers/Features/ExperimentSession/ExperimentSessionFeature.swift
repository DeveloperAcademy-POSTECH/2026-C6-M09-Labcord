import ComposableArchitecture
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
    }

    enum Action: Equatable {
        case timerTabSelected(TimerTab)
        case cameraPermission(CameraPermssionFeature.Action)
    }

    var body: some Reducer<State, Action> {
        Scope(state: \.cameraPermission, action: \.cameraPermission) {
            CameraPermssionFeature()
        }
        
        Reduce { state, action in
            switch action {
            case let .timerTabSelected(tab):
                state.selectedTimerTab = tab
                return .none
                
            case .cameraPermission:
                return .none
            }
        }
    }
}
