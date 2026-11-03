//
//  OnboardingFeature.swift
//  Researchers
//
//  Created by lwc0113 on 11/2/26.
//

import ComposableArchitecture

@Reducer
// 1. TCA Feature표시
struct OnboardingFeature {

    enum Page: Int, Equatable {
// 2. 페이지종류
        case first, second, third
    }

    @ObservableState
// 3. View가 변화를 자동감지
    struct State: Equatable {
        var page: Page = .first
// 4. 바뀌는 값만
    }

    enum Action: Equatable {
// 5. 사용자 동작 몽록
        case nextTapped
        case previousTapped
        case skipTapped
        case startTapped
    }

    var body: some Reducer<State, Action> {
// 6. 규칙: Action > State 변화
        Reduce { state, action in
            switch action {
            case.nextTapped:
                guard let next =
                        Page(rawValue: state.page.rawValue + 1)
                        else { return.none
                }
                state.page = next
                return.none

            case .previousTapped:
                guard let previous = Page(rawValue: state.page.rawValue - 1)
                        else {
                return .none
            }
            state.page = previous
            return.none

        case .skipTapped, .startTapped:
            return .none

            }
        }
    }
}
