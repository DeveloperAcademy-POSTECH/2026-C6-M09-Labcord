import ComposableArchitecture
import LabcordiOS

extension AppFeature {
    var settingsReturnReducer: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .watchSceneChanged(active):
                if active, let id = state.path.ids.last,
                   let session = state.path[id: id, case: \.session],
                   SettingsReturnSessionStore.experimentID == session.experimentID {
                    SettingsReturnSessionStore.clear()
                }
                return .none

            case .restoreSettingsSession:
                guard state.path.isEmpty,
                      let experimentID = SettingsReturnSessionStore.experimentID else {
                    return .none
                }
                return .run { send in
                    let exists = (try? await experimentClient.load())?.contains {
                        $0.id == experimentID && $0.status != .completed
                    } == true
                    await send(.settingsSessionLoaded(experimentID, exists))
                }

            case let .settingsSessionLoaded(experimentID, exists):
                guard SettingsReturnSessionStore.experimentID == experimentID else { return .none }
                SettingsReturnSessionStore.clear()
                guard exists, state.path.isEmpty, !state.reviewSaving else { return .none }
                state.path.append(.session(.init(experimentID: experimentID)))
                return .send(.home(.list(.cancelLoad)))

            case let .path(.element(id: id, action: .session(.permissions(.openSettingsTapped)))):
                if let session = state.path[id: id, case: \.session],
                   !session.isReturningHome {
                    SettingsReturnSessionStore.save(session.experimentID)
                }
                return .none

            case .path(.element(_, action: .session(.permissions(.openSettingsFailed)))):
                SettingsReturnSessionStore.clear()
                return .none

            case let .returnHome(id):
                guard state.path.ids.last == id else { return .none }
                SettingsReturnSessionStore.clear()
                return .none

            default:
                return .none
            }
        }
    }
}

extension AppFeature {
    func openResumedSession(_ state: inout State, id: StackElementID) -> Effect<Action> {
        guard var result = state.path[id: id, case: \.result], result.isResuming else {
            return .none
        }
        guard state.path.ids.last == id else {
            result.isResuming = false
            state.path[id: id, case: \.result] = result
            return .none
        }
        state.path.removeAll()
        state.path.append(.session(.init(experimentID: result.experimentID)))
        return .none
    }
}
