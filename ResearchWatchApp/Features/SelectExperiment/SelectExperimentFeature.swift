import ComposableArchitecture
import Foundation
import LabcordShared
import LabcordWatchOS

@Reducer
struct SelectExperimentFeature {
    @ObservableState
    struct State: Equatable {
        var experiments: [WatchExperimentSummary] = []
        var isLoading = false
        var errorMessage: String?
    }

    enum Action {
        case appeared
        case experimentTapped(UUID)
        case disappeared
        case listUpdated([WatchExperimentSummary])
        case loadSucceeded([WatchExperimentSummary])
        case loadFailed
    }

    private nonisolated enum CancelID: Hashable, Sendable {
        case load
        case listUpdates
    }

    @Dependency(\.watchExperimentClient) var watchExperimentClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .appeared:
                let loadEffect = load(&state)
                return .merge(
                    loadEffect,
                    .run { send in
                        for await experiments in await watchExperimentClient.lists() {
                            await send(.listUpdated(experiments))
                        }
                    }
                    .cancellable(id: CancelID.listUpdates, cancelInFlight: true)
                )
            case let .experimentTapped(id):
                return .run { _ in
                    await watchExperimentClient.requestPhoneSession(id)
                }
            case .disappeared:
                state.isLoading = false
                return .merge(
                    .cancel(id: CancelID.load),
                    .cancel(id: CancelID.listUpdates)
                )
            case let .listUpdated(experiments):
                let wasLoading = state.isLoading
                state.experiments = experiments
                state.isLoading = false
                state.errorMessage = nil
                return wasLoading ? .cancel(id: CancelID.load) : .none
            case let .loadSucceeded(experiments):
                guard state.isLoading else { return .none }
                state.experiments = experiments
                state.isLoading = false
                state.errorMessage = nil
                return .none
            case .loadFailed:
                guard state.isLoading else { return .none }
                state.isLoading = false
                state.errorMessage = "실험을 불러오지 못했어요.\n다시 시도해 주세요."
                return .none
            }
        }
    }

    private func load(_ state: inout State) -> Effect<Action> {
        guard !state.isLoading else { return .none }
        state.isLoading = true
        state.errorMessage = nil
        return .run { send in
            do {
                let experiments = try await watchExperimentClient.list()
                await send(.loadSucceeded(experiments))
            } catch {
                await send(.loadFailed)
            }
        }
        .cancellable(id: CancelID.load, cancelInFlight: true)
    }
}
