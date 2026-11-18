//
//  SortRecordFeature.swift
//  Researchers
//
//  Created by 정홍섭 on 11/18/26.
//

import ComposableArchitecture

@Reducer
struct SortRecordFeature {
    @ObservableState
    struct State: Equatable {
        var isPhoneResultReady = false
        var shouldClose = false
    }

    enum Action {
        case phoneResultReady
        case closeTapped
        case timeout
        case disappeared
    }

    private nonisolated enum CancelID: Hashable, Sendable {
        case autoClose
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .phoneResultReady:
                guard !state.isPhoneResultReady else { return .none }
                state.isPhoneResultReady = true
                return .run { send in
                    try await Task.sleep(for: .seconds(5))
                    await send(.timeout)
                }
                .cancellable(id: CancelID.autoClose, cancelInFlight: true)

            case .closeTapped, .timeout:
                guard state.isPhoneResultReady, !state.shouldClose else { return .none }
                state.shouldClose = true
                return .cancel(id: CancelID.autoClose)

            case .disappeared:
                return .cancel(id: CancelID.autoClose)
            }
        }
    }
}
