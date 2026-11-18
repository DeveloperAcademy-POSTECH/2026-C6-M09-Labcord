//
//  AddTimerFeature.swift
//  ResearchWatch Watch App
//
//  Created by 정홍섭 on 11/17/26.
//

import ComposableArchitecture
import Foundation

@Reducer
struct AddTimerFeature {
    @ObservableState
    struct State: Equatable {
        var hours = 0
        var minutes = 0
        var seconds = 0

        var canAddTimer: Bool
        var requestedSeconds: Int?

        var totalSeconds: Int {
            hours * 3_600 + minutes * 60 + seconds
        }

        var canStart: Bool {
            totalSeconds > 0 && canAddTimer && requestedSeconds == nil
        }

        init(canAddTimer: Bool) {
            self.canAddTimer = canAddTimer
        }
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case canAddTimerChanged(Bool)
        case startTapped
    }

    var body: some Reducer<State, Action> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding:
                return .none
            case let .canAddTimerChanged(canAddTimer):
                state.canAddTimer = canAddTimer
                return .none
            case .startTapped:
                guard state.canStart else { return .none }
                state.requestedSeconds = state.totalSeconds
                return .none
            }
        }
    }
}
