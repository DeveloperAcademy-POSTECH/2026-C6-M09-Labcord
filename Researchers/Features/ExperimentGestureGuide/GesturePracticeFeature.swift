import ComposableArchitecture

@Reducer
struct GesturePracticeFeature {
    @ObservableState
    struct State: Equatable {
        var device: GestureDevice
    }

    enum Action {
        case deviceChanged(GestureDevice)
        case backTapped
        case exitTapped
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            if case let .deviceChanged(device) = action {
                state.device = device
            }
            return .none
        }
    }
}
