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
        case disappeared
        case cacheLoaded([WatchExperimentSummary])
        case listUpdated([WatchExperimentSummary])
        case loadSucceeded([WatchExperimentSummary])
        case loadFailed(WatchExperimentError?)
        case retryTapped
    }

    private nonisolated enum CancelID: Hashable, Sendable {
        case cache
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
                    .run { send in
                        if let cached = await watchExperimentClient.cachedList() {
                            await send(.cacheLoaded(cached))
                        }
                    }
                    .cancellable(id: CancelID.cache, cancelInFlight: true),
                    loadEffect,
                    .run { send in
                        for await experiments in await watchExperimentClient.lists() {
                            await send(.listUpdated(experiments))
                        }
                    }
                    .cancellable(id: CancelID.listUpdates, cancelInFlight: true)
                )
            case .disappeared:
                state.isLoading = false
                return .merge(
                    .cancel(id: CancelID.cache),
                    .cancel(id: CancelID.load),
                    .cancel(id: CancelID.listUpdates)
                )
            case let .cacheLoaded(experiments):
                // 캐시는 iPhone 응답 전 임시 표시용이므로 로딩·최신 응답을 덮어쓰지 않습니다.
                guard state.isLoading, state.experiments.isEmpty else { return .none }
                state.experiments = experiments
                return .none
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
            case let .loadFailed(error):
                guard state.isLoading else { return .none }
                state.isLoading = false
                state.errorMessage = Self.message(for: error)
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
                let experiments = try await watchExperimentClient.list()
                await send(.loadSucceeded(experiments))
            } catch {
                await send(.loadFailed(error as? WatchExperimentError))
            }
        }
        .cancellable(id: CancelID.load, cancelInFlight: true)
    }

    private static func message(for error: WatchExperimentError?) -> String {
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
