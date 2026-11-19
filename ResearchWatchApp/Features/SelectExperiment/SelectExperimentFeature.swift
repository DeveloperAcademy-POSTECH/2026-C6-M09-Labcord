import ComposableArchitecture
import LabcordShared
import LabcordWatchOS

@Reducer
struct SelectExperimentFeature {
    @ObservableState
    struct State: Equatable {
        var list: WatchExperimentList?
        var isLoading = false
        var errorMessage: String?

        var experiments: [WatchExperimentSummary] { list?.experiments ?? [] }
    }

    enum Action {
        case appeared
        case disappeared
        case listUpdated(WatchExperimentListUpdate)
        case loadFinished(WatchExperimentError?)
        case retryTapped
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
                        for await update in await watchExperimentClient.lists() {
                            await send(.listUpdated(update))
                        }
                    }
                    .cancellable(id: CancelID.listUpdates, cancelInFlight: true)
                )

            case .disappeared:
                state.isLoading = false
                return .merge(.cancel(id: CancelID.load), .cancel(id: CancelID.listUpdates))

            case let .listUpdated(.snapshot(list)):
                state.list = list
                return .none

            case let .listUpdated(.invalidated(epoch)):
                if state.list?.version?.epoch != epoch { state.list = nil }
                return .none

            case let .loadFinished(error):
                state.isLoading = false
                state.errorMessage = error.map(Self.message(for:))
                return .none

            case .retryTapped:
                return load(&state)
            }
        }
    }

    private func load(_ state: inout State) -> Effect<Action> {
        guard !state.isLoading else { return .none }
        state.isLoading = true
        state.errorMessage = nil
        return .run { send in
            do {
                _ = try await watchExperimentClient.list()
                await send(.loadFinished(nil))
            } catch is CancellationError {
                return
            } catch {
                await send(.loadFinished(error as? WatchExperimentError ?? .resultUnknown))
            }
        }
        .cancellable(id: CancelID.load, cancelInFlight: true)
    }

    private nonisolated static func message(for error: WatchExperimentError) -> String {
        switch error {
        case .notReachable:
            "iPhone과 연결할 수 없어요."
        case .deliveryTimeout:
            "iPhone 응답이 늦어지고 있어요."
        case .phoneUnlockRequired:
            "iPhone 잠금을 해제해 주세요."
        case .storageFailed:
            "iPhone에서 실험을 읽지 못했어요."
        default:
            "실험을 불러오지 못했어요."
        }
    }
}
