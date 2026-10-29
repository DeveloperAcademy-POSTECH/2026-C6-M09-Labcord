import ComposableArchitecture

@Reducer
struct HomeFeature {
    @ObservableState
    struct State: Equatable {
        var list = ExperimentListFeature.State()
    }

    enum Action {
        case list(ExperimentListFeature.Action)
        case addTapped
        case settingsTapped
    }

    var body: some Reducer<State, Action> {
        Scope(state: \.list, action: \.list) { ExperimentListFeature() }

        Reduce { _, action in
            switch action {
            case .addTapped, .settingsTapped, .list:
                return .none
            }
        }
    }
}
