import ComposableArchitecture

extension AppFeature {
    var gestureGuideReducer: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .home(.gestureGuideTapped):
                guard state.path.isEmpty, !state.home.list.isDeleting,
                      state.home.list.pendingDeletion == nil else { return .none }
                state.path.append(.gestureGuide(GestureGuideFeature.State()))
                return .send(.home(.list(.cancelLoad)))
            case let .path(.element(id: id, action: .gestureGuide(.exitTapped))):
                guard state.path.ids.last == id else { return .none }
                state.path.pop(from: id)
                return .none
            default:
                return .none
            }
        }
    }
}
