import ComposableArchitecture
import LabcordShared
import LabcordWatchOS

@Reducer
struct SelectExperimentFeature {
    @ObservableState
    struct State: Equatable {
        var list: WatchExperimentList?
        var epoch: WatchStateEpoch?
        var isLoading = false
        var errorMessage: String?

        var experiments: [WatchExperimentSummary] { list?.experiments ?? [] }
    }

    enum Action {
        case appeared
        case disappeared
        case listUpdated(WatchExperimentListUpdate)
        case loadFinished(Result<WatchExperimentList, WatchExperimentError>)
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
                accept(list, state: &state)
                return .none

            case let .listUpdated(.invalidated(epoch)):
                if let previous = state.epoch, !epoch.isNewer(than: previous) { return .none }
                state.epoch = epoch
                state.list = nil
                return load(&state)

            case let .loadFinished(result):
                state.isLoading = false
                switch result {
                case let .success(list):
                    accept(list, state: &state)
                    if state.list == nil { state.errorMessage = Self.message(for: .staleRevision) }
                case let .failure(error):
                    state.errorMessage = Self.message(for: error)
                }
                return .none

            case .retryTapped:
                return load(&state)
            }
        }
    }

    private func accept(_ list: WatchExperimentList, state: inout State) {
        if let expected = state.epoch {
            guard let epoch = list.version?.epoch,
                  epoch == expected || epoch.isNewer(than: expected) else { return }
        }
        if let current = state.list?.version, let incoming = list.version,
           incoming != current, !incoming.isNewer(than: current) { return }
        state.epoch = list.version?.epoch
        state.list = list
        state.errorMessage = nil
    }

    private func load(_ state: inout State) -> Effect<Action> {
        guard !state.isLoading else { return .none }
        state.isLoading = true
        state.errorMessage = nil
        return .run { send in
            do {
                let list = try await watchExperimentClient.list()
                try Task.checkCancellation()
                await send(.loadFinished(.success(list)))
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                let failure = error as? WatchExperimentError ?? .resultUnknown
                await send(.loadFinished(.failure(failure)))
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
