import ComposableArchitecture

@Reducer
struct ProtocolAnalysisProgressFeature {
    @ObservableState
    struct State: Equatable {
        var showSkipConfirmation = false
        var showExitConfirmation = false
    }

    enum Action: Equatable {
        case skipTapped
        case backTapped
        case dismissSkipConfirmation
        case dismissExitConfirmation
        case confirmSkip
        case confirmExit
        case delegate(Delegate)
    }

    enum Delegate: Equatable {
        case skip
        case exit
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .skipTapped:
                state.showSkipConfirmation = true
            case .backTapped:
                state.showExitConfirmation = true
            case .dismissSkipConfirmation:
                state.showSkipConfirmation = false
            case .dismissExitConfirmation:
                state.showExitConfirmation = false
            case .confirmSkip:
                state.showSkipConfirmation = false
                return .send(.delegate(.skip))
            case .confirmExit:
                state.showExitConfirmation = false
                return .send(.delegate(.exit))
            case .delegate:
                break
            }
            return .none
        }
    }
}
