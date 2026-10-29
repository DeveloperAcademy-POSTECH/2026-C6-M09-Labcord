//
//  LandscapeSessionView.swift
//  Researchers
//
//  Created by 정홍섭 on 10/25/26.
//

import ComposableArchitecture
import SwiftUI

struct LandscapeSessionView: View {
    let store: StoreOf<CameraCaptureFeature>
    let timerStore: StoreOf<SessionTimerFeature>
    let sessionStore: StoreOf<ExperimentSessionFeature>

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear

            VStack(alignment: .leading, spacing: 20) {
                SessionHeaderView(store: sessionStore)

                HStack(alignment: .top, spacing: 20) {
                    CameraCaptureView(store: store)

                    Spacer()

                    SessionTimerView(store: timerStore)
                }
            }
            .padding(.vertical, 30)
            .padding(.leading, 80)
            .padding(.trailing, 36)
            .foregroundStyle(.white)
        }
        .ignoresSafeArea()
    }
}

#Preview {
    LandscapeSessionView(
        store: Store(initialState: CameraCaptureFeature.State()) {
            CameraCaptureFeature()
        },
        timerStore: Store(initialState: SessionTimerFeature.State()) {
            SessionTimerFeature()
        },
        sessionStore: Store(initialState: ExperimentSessionFeature.State()) {
            ExperimentSessionFeature()
        }
    )
}
