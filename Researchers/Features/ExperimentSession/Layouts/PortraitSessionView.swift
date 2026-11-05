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
    @Binding var isSidePanelExpanded: Bool

    let store: StoreOf<CameraCaptureFeature>
    let timerStore: StoreOf<SessionTimerFeature>
    let sessionStore: StoreOf<ExperimentSessionFeature>

    var body: some View {
        GeometryReader { _ in
            ZStack {
                Color.clear
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    VStack {
                        HeaderView(store: sessionStore)
                            .padding(16)

                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .anchorPreference(key: CameraPreviewAnchorKey.self, value: .bounds) { $0 }

                    ExperimentSidePanel(
                        layout: .portrait,
                        isExpanded: $isSidePanelExpanded
                    )
                    .ignoresSafeArea()
                    .frame(height: isSidePanelExpanded ? 398 : 83)
                }
            }
            .foregroundStyle(.white)
        }
    }
}

#Preview {
    @Previewable @State var isSidePanelExpanded = true

    PortraitSessionView(
        isSidePanelExpanded: $isSidePanelExpanded,
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
