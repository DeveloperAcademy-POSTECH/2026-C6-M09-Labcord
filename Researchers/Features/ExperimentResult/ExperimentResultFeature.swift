//
//  ExperimentResultFeature.swift
//  Researchers
//
//  Created by 정홍섭 on 10/29/26.
//

import ComposableArchitecture

@Reducer
struct ExperimentResultFeature {
    @ObservableState
    struct State: Equatable {}

    enum Action: Equatable {
        case homeTapped
    }

    var body: some Reducer<State, Action> {
        Reduce { _, action in
            switch action {
            case .homeTapped:
                return .none
            }
        }
    }
}
