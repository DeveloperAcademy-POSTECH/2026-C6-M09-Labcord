//
//  PortraitSessionView.swift
//  Researchers
//
//  Created by 정홍섭 on 10/25/26.
//

import ComposableArchitecture
import SwiftUI

struct PortraitSessionView: View {
    let store: StoreOf<CameraCaptureFeature>
    let timerStore: StoreOf<SessionTimerFeature>
    let sessionStore: StoreOf<ExperimentSessionFeature>

    var body: some View {
        GeometryReader { geo in
            let screenHeight = geo.size.height
            + geo.safeAreaInsets.top
            + geo.safeAreaInsets.bottom

            ZStack {
                Color.clear
                    .ignoresSafeArea()

                VStack {
                    SessionHeaderView(store: sessionStore)
                        .padding(16)

                    Spacer()
                }

                PortraitSessionSheetView(
                    store: store,
                    timerStore: timerStore,
                    compactHeight: screenHeight * 0.127,
                    expandedHeight: screenHeight * 0.3890160183,
                    bottomInset: geo.safeAreaInsets.bottom
                )
            }
            .foregroundStyle(.white)
        }
    }
}

#Preview {
    PortraitSessionView(
        store: Store(
            initialState: CameraCaptureFeature.State()
        ) {
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
