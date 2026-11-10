import ComposableArchitecture

@Reducer
struct GestureGuideFeature {
    @ObservableState
    struct State: Equatable {
        var device: GestureDevice = .iPhone
        var isPracticing = false
    }

    enum Action {
        case deviceChanged(GestureDevice)
        case practiceTapped
        case backTapped
        case exitTapped
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .deviceChanged(device):
                state.device = device
            case .practiceTapped:
                state.isPracticing = true
            case .backTapped:
                state.isPracticing = false
            case .exitTapped:
                break
            }
            return .none
        }
    }
}
