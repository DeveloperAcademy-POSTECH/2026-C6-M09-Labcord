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
        var isCurrent = false
        var reachable: Bool?
        var lastPublishedList: [WatchExperimentSummary]?
        var errorMessage: String?
    }

    enum Action {
        case appeared
        case disappeared
        case cacheLoaded([WatchExperimentSummary])
        case listUpdated([WatchExperimentSummary])
        case loadSucceeded([WatchExperimentSummary])
        case loadFailed(WatchExperimentError?)
        case reachabilityChanged(Bool)
        case retryTapped
    }

    private nonisolated enum CancelID: Hashable, Sendable {
        case reachability
        case cache
        case load
        case listUpdates
    }

    @Dependency(\.watchConnectivitySession) var connectivity
    @Dependency(\.watchExperimentClient) var watchExperimentClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .appeared:
                state.isCurrent = false
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
                        for await reachable in await connectivity.reachabilityChanges() {
                            await send(.reachabilityChanged(reachable))
                        }
                    }
                    .cancellable(id: CancelID.reachability, cancelInFlight: true),
                    .run { send in
                        for await experiments in await watchExperimentClient.lists() {
                            await send(.listUpdated(experiments))
                        }
                    }
                    .cancellable(id: CancelID.listUpdates, cancelInFlight: true)
                )
            case .disappeared:
                state.isLoading = false
                state.isCurrent = false
                state.reachable = nil
                state.lastPublishedList = nil
                return .merge(
                    .cancel(id: CancelID.reachability),
                    .cancel(id: CancelID.cache),
                    .cancel(id: CancelID.load),
                    .cancel(id: CancelID.listUpdates)
                )
            case let .cacheLoaded(experiments):
                // 캐시는 iPhone 응답 전 임시 표시용이므로 로딩·최신 응답을 덮어쓰지 않습니다.
                guard !state.isCurrent, state.experiments.isEmpty, state.lastPublishedList == nil
                else { return .none }
                state.experiments = experiments
                return .none
            case let .listUpdated(experiments):
                guard state.lastPublishedList != experiments else { return .none }
                state.lastPublishedList = experiments
                guard state.experiments != experiments else { return .none }
                if !state.isCurrent { state.experiments = experiments }
                return load(&state)
            case let .reachabilityChanged(reachable):
                let previous = state.reachable
                state.reachable = reachable
                if !reachable { state.isCurrent = false }
                guard previous == false, reachable else { return .none }
                return load(&state, restart: true)
            case let .loadSucceeded(experiments):
                guard state.isLoading else { return .none }
                state.experiments = experiments
                state.isCurrent = true
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

    private func load(_ state: inout State, restart: Bool = false) -> Effect<Action> {
        guard restart || !state.isLoading else { return .none }
        state.isLoading = true
        state.isCurrent = false
        state.errorMessage = nil
        return .run { send in
            do {
                let experiments = try await watchExperimentClient.list()
                try Task.checkCancellation()
                await send(.loadSucceeded(experiments))
            } catch {
                guard !Task.isCancelled else { return }
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
