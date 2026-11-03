//
//  OnboardingFeature.swift
//  Researchers
//
//  Created by lwc0113 on 11/2/26.
//

import ComposableArchitecture

@Reducer
struct OnboardingFeature {

    enum Page: Int, Equatable {
        case first, second, third
    }

    @ObservableState
    struct State: Equatable {
        var page: Page = .first
    }

    enum Action: Equatable {
        case nextTapped
        case previousTapped
        case skipTapped
        case startTapped
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .nextTapped:
                guard let next =
                        Page(rawValue: state.page.rawValue + 1)
                        else { return .none
                }
                state.page = next
                return .none

            case .previousTapped:
                guard let previous = Page(rawValue: state.page.rawValue - 1)
                        else {
                    return .none
                }
                state.page = previous
                return .none

            case .skipTapped, .startTapped:
                return .none

            }
        }
    }
}
