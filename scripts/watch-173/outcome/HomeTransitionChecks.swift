import Foundation

enum AppState { case active, background }
final class UIApplication {
    static let shared = UIApplication()
    var applicationState = AppState.active
}
struct Effect<Action> {
    static var none: Self { Self() }
    static func send(_ action: Action) -> Self { Self() }
}
struct Reduce<State, Action> {
    let body: (inout State, Action) -> Effect<Action>
    init(_ body: @escaping (inout State, Action) -> Effect<Action>) { self.body = body }
}
final class PhoneWatchExperimentCoordinator {
    static let shared = PhoneWatchExperimentCoordinator()
    var visibleExperimentID: UUID?
    var isBusy = false
    var opened: [UUID] = []
    func refresh() {}
    func didOpen(_ id: UUID) { opened.append(id) }
}
struct SessionState { let experimentID: UUID }
enum PathState {
    case session(SessionState)
    case registration
    var sessionValue: SessionState? {
        if case let .session(value) = self { return value }
        return nil
    }
}
struct Path {
    var values: [PathState] = []
    var ids: [Int] { Array(values.indices) }
    var isEmpty: Bool { values.isEmpty }
    subscript(id id: Int, case key: KeyPath<PathState, SessionState?>) -> SessionState? {
        values[id][keyPath: key]
    }
    mutating func append(_ value: PathState) { values.append(value) }
}
enum Status { case running, paused }
struct WatchState { var experiment: Experiment; struct Experiment { var status: Status } }
struct Client {
    var status: Status = .running
    func watchState(_ id: UUID) throws -> WatchState? {
        WatchState(experiment: .init(status: status))
    }
}
struct ListState { var isDeleting = false; var pendingDeletion: UUID? }
struct HomeState { var list = ListState() }
enum ListAction { case cancelLoad }
enum HomeAction { case list(ListAction) }
struct AppFeature {
    struct State {
        var watchIsActive = true
        var watchPendingStartID: UUID?
        var reviewSaving = false
        var path = Path()
        var home = HomeState()
    }
    enum Action {
        case home(HomeAction)
        case other
    }
    var experimentClient = Client()
    // ACTUAL_CONTEXT_REDUCER
    // ACTUAL_OPEN_WATCH_SESSION
}

@main
struct Checks {
    @MainActor static func main() {
        let id = UUID()
        let feature = AppFeature()
        var state = AppFeature.State(watchPendingStartID: id)
        state.path.values = [.registration]
        _ = feature.watchContextReducer.body(&state, .other)
        precondition(state.watchPendingStartID == id && state.path.values.count == 1)
        print("PASS: pending start waits while registration is open")
        state.path.values = []
        _ = feature.watchContextReducer.body(&state, .other)
        precondition(state.watchPendingStartID == nil)
        precondition(state.path.values.first?.sessionValue?.experimentID == id)
        print("PASS: pending start opens after returning home")
        state.path.values = []
        state.watchPendingStartID = id
        state.watchIsActive = false
        _ = feature.watchContextReducer.body(&state, .other)
        precondition(state.watchPendingStartID == id && state.path.isEmpty)
        print("PASS: background state keeps pending start")
        state.watchIsActive = true
        state.home.list.pendingDeletion = UUID()
        _ = feature.watchContextReducer.body(&state, .other)
        precondition(state.watchPendingStartID == id && state.path.isEmpty)
        print("PASS: deletion confirmation blocks auto transition")
    }
}
