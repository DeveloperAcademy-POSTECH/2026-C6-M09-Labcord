//
//  PortraitSessionView.swift
//  Researchers
//
//  Created by 정홍섭 on 10/25/26.
//

import ComposableArchitecture
import LabcordDesignSystem
import SwiftUI

struct PortraitSessionView: View {
    @State private var isSidePanelExpanded = true

    let store: StoreOf<CameraCaptureFeature>
    let timerStore: StoreOf<SessionTimerFeature>
    let sessionStore: StoreOf<ExperimentSessionFeature>

    var body: some View {
        GeometryReader { _ in
            ZStack {
                Color.clear
                    .ignoresSafeArea()

                VStack {
                    HeaderView(store: sessionStore)
                        .padding(16)

                    Spacer()

                    ExperimentSidePanel(
                        layout: .portrait,
                        isExpanded: $isSidePanelExpanded
                    )
                    .ignoresSafeArea()
                    .frame(height: 398)
                }
            }
            .foregroundStyle(.white)
        }
    }
}

#Preview {
    PortraitSessionView(
        store: Store(
            initialState: CameraCaptureFeature.State(experimentID: UUID())
        ) {
            CameraCaptureFeature()
        },
        timerStore: Store(initialState: SessionTimerFeature.State()) {
            SessionTimerFeature()
        },
        sessionStore: Store(
            initialState: ExperimentSessionFeature.State(experimentID: UUID())
        ) {
            ExperimentSessionFeature()
        }
    )
}
