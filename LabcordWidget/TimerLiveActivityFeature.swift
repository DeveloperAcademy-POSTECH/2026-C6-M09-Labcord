//
//  TimerLiveActivityFeature.swift
//  LabcordWidgetExtension
//
//  Created by 정홍섭 on 11/14/26.
//

import ComposableArchitecture
import Foundation
import LabcordShared

@Reducer
struct TimerLiveActivityFeature {
    @ObservableState
    struct State: Equatable {
        let experimentID: UUID
        let experimentTitle: String
        var timer: TimerActivityAttributes.ContentState

        init(
            attributes: TimerActivityAttributes,
            contentState: TimerActivityAttributes.ContentState
        ) {
            experimentID = attributes.experimentID
            experimentTitle = attributes.experimentTitle
            timer = contentState
        }
    }

    enum Action: Equatable {
        case contentStateChanged(TimerActivityAttributes.ContentState)
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .contentStateChanged(contentState):
                state.timer = contentState
                return .none
            }
        }
    }
}
