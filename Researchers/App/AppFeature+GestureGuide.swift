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
            case let .path(.element(id: id, action: .gestureGuide(.practiceTapped))):
                guard state.path.ids.last == id,
                      let guide = state.path[id: id, case: \.gestureGuide] else { return .none }
                state.path.append(.gesturePractice(.init(device: guide.device)))
                return .none
            case let .path(.element(id: id, action: .gesturePractice(.deviceChanged(device)))):
                guard state.path.ids.last == id,
                      let guideID = state.path.ids.dropLast().last,
                      var guide = state.path[id: guideID, case: \.gestureGuide] else {
                    return .none
                }
                guide.device = device
                state.path[id: guideID, case: \.gestureGuide] = guide
                return .none
            case let .path(.element(id: id, action: .gesturePractice(.backTapped))):
                guard state.path.ids.last == id else { return .none }
                state.path.pop(from: id)
                return .none
            case let .path(.element(id: id, action: .gesturePractice(.practiceReady))):
                guard state.path.ids.last == id else { return .none }
                state.home.$requiresGesturePractice.withLock { $0 = false }
                state.home.isGuideVisible = false
                return .none
            case let .path(.element(id: id, action: .gesturePractice(.exitTapped))):
                guard state.path.ids.last == id,
                      let guideID = state.path.ids.dropLast().last,
                      state.path[id: guideID, case: \.gestureGuide] != nil else { return .none }
                state.home.$requiresGesturePractice.withLock { $0 = false }
                state.home.isGuideVisible = false
                state.path.pop(from: guideID)
                return .none
            case let .path(.element(id: id, action: .gestureGuide(.exitTapped))):
                guard state.path.ids.last == id else { return .none }
                state.home.$requiresGesturePractice.withLock { $0 = false }
                state.home.isGuideVisible = false
                state.path.pop(from: id)
                return .none
            case let .path(.popFrom(id: id)):
                guard state.path[id: id, case: \.gestureGuide] != nil else { return .none }
                state.home.$requiresGesturePractice.withLock { $0 = false }
                state.home.isGuideVisible = false
                return .none
            default:
                return .none
            }
        }
    }
}
