import ComposableArchitecture

@Reducer
struct ExperimentSessionFeature {
    enum TimerTab: Equatable {
        case configured
        case active
    }

    @ObservableState
    struct State: Equatable {
        var selectedTimerTab: TimerTab = .configured
    }

    enum Action: Equatable {
        case timerTabSelected(TimerTab)
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .timerTabSelected(tab):
                state.selectedTimerTab = tab
                return .none
            }
        }
    }
}
