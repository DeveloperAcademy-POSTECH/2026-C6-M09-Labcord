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
        var timerSeconds: [Int] = [5400, 120, 10, 5, 120, 30, 60, 900, 2000, 2500, 3000, 150]
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
