import ComposableArchitecture
import Foundation
import LabcordiOS

@Reducer
struct RecentProtocolFeature {
    @ObservableState
    struct State: Equatable {
        var entries: [RecentProtocolEntry] = []
        var selectedID: UUID?
        var loading = false
        var failed = false
    }

    enum Action: Equatable {
        case load
        case loaded([RecentProtocolEntry])
        case loadFailed
        case select(UUID)
        case useSelected
        case backTapped
    }

    @Dependency(\.experimentClient) var experimentClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .load:
                guard !state.loading else { return .none }
                state.loading = true
                state.failed = false
                return .run { send in
                    do {
                        await send(.loaded(try await experimentClient.loadRecentProtocols()))
                    } catch {
                        await send(.loadFailed)
                    }
                }
            case let .loaded(entries):
                state.loading = false
                state.entries = entries
                if !entries.contains(where: { $0.id == state.selectedID }) {
                    state.selectedID = nil
                }
                return .none
            case .loadFailed:
                state.loading = false
                state.failed = true
                return .none
            case let .select(id):
                guard state.entries.contains(where: { $0.id == id }) else { return .none }
                state.selectedID = id
                return .none
            case .useSelected, .backTapped:
                return .none
            }
        }
    }
}
