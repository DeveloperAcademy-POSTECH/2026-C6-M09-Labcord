import ComposableArchitecture
import LabcordiOS

@Reducer
struct AppFeature {
    @Reducer
    enum Path {
        case registration(ProtocolRegistrationFeature)
        case session(ExperimentSessionFeature)
        case result(ExperimentResultFeature)
    }

    @ObservableState
    struct State: Equatable {
        var home = HomeFeature.State()
        var path = StackState<Path.State>()
    }

    enum Action {
        case home(HomeFeature.Action)
        case path(StackActionOf<Path>)
        case closeRegistration(StackElementID)
        case registrationSucceeded(StackElementID, ExperimentListEntry)
        case showResult(StackElementID)
        case returnHome(StackElementID)
    }

    var body: some Reducer<State, Action> {
        Scope(state: \.home, action: \.home) { HomeFeature() }

        Reduce { state, action in
            switch action {
            case .home(.addTapped):
                guard state.path.isEmpty, !state.home.list.isDeleting,
                      state.home.list.pendingDeletion == nil else { return .none }
                state.path.append(.registration(ProtocolRegistrationFeature.State()))
                return .send(.home(.list(.cancelLoad)))

            case let .home(.list(.experimentTapped(identifier))):
                guard state.path.isEmpty, !state.home.list.isDeleting,
                      state.home.list.entries.contains(where: { $0.id == identifier }) else {
                    return .none
                }
                state.path.append(.session(ExperimentSessionFeature.State()))
                return .send(.home(.list(.cancelLoad)))

            case let .path(.element(id: id, action: .registration(.backTapped))):
                return .send(.closeRegistration(id))

            case let .closeRegistration(id):
                guard state.path[id: id, case: \.registration]?.isSaving == false else {
                    return .none
                }
                state.path.pop(from: id)
                return .none

            case let .path(.element(id: id, action: .registration(.saveSucceeded(entry)))):
                return .send(.registrationSucceeded(id, entry))

            case let .registrationSucceeded(id, entry):
                guard state.path.ids.last == id else { return .none }
                state.path.append(.session(ExperimentSessionFeature.State()))
                return .send(.home(.list(.created(entry))))

            case let .path(.element(id: id, action: .session(.stopTapped))):
                return .send(.showResult(id))

            case let .path(.element(id: id, action: .session(.homeExitCompleted))):
                return .send(.returnHome(id))

            case let .showResult(id):
                guard state.path.ids.last == id else { return .none }
                state.path.append(.result(ExperimentResultFeature.State()))
                return .none

            case let .path(.element(id: id, action: .result(.homeTapped))):
                return .send(.returnHome(id))

            case let .returnHome(id):
                guard state.path.ids.last == id else { return .none }
                state.path.removeAll()
                return .none

            case .home, .path:
                return .none
            }
        }
        .forEach(\.path, action: \.path)
    }
}

extension AppFeature.Path.State: Equatable {}
