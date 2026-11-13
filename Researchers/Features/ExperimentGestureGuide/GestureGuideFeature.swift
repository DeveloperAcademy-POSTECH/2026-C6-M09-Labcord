import ComposableArchitecture

@Reducer
struct GestureGuideFeature {
    @ObservableState
    struct State: Equatable {
        var device: GestureDevice = .iPhone
    }

    enum Action {
        case deviceChanged(GestureDevice)
        case practiceTapped
        case exitTapped
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .deviceChanged(device):
                state.device = device
            case .practiceTapped, .exitTapped:
                break
            }
            return .none
        }
    }
}
