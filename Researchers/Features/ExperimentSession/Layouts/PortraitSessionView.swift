//
//  PortraitSessionView.swift
//  Researchers
//
//  Created by 정홍섭 on 10/25/26.
//

import ComposableArchitecture
import LabcordDesignSystem
import LabcordShared
import SwiftUI

struct PortraitSessionView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var isSidePanelExpanded: Bool

    let store: StoreOf<CameraCaptureFeature>
    let timerStore: StoreOf<SessionTimerFeature>
    let sessionStore: StoreOf<ExperimentSessionFeature>
    let onShowGestureGuide: () -> Void

    private var areRecordButtonsDisabled: Bool {
        sessionStore.voice.phase != .hidden
            || store.previewConnector == nil
            || store.isCameraSwitching
            || store.isPhotoCaptureScheduled
            || store.isCapturingPhoto
            || store.capturedPhotoData != nil
            || store.videoPhase != .idle
    }

    var body: some View {
        GeometryReader { _ in
            ZStack {
                Color.clear
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    VStack(alignment: .trailing, spacing: 18) {
                        HeaderView(store: sessionStore)
                            .padding(16)

                        ExperimentRecordButtonsView(
                            store: store,
                            isDisabled: areRecordButtonsDisabled
                        )

                        Spacer()
                    }
                    .frame(maxWidth: .infinity)

                    VStack {
                        ExperimentSettingButtonsView(
                            onShowGestureGuide: onShowGestureGuide,
                            onShowRunningTimers: {
                                timerStore.send(.timerTabSelected(.active))
                                withAnimation(
                                    reduceMotion ? nil : LabcordMotion.layout.animation
                                ) {
                                    isSidePanelExpanded = true
                                }
                            },
                            onSwitchCamera: { store.send(.cameraSwitchRequested) },
                            showsRunningTimerButton: !isSidePanelExpanded
                                && timerStore.timerCollection.hasRunningTimers,
                            canSwitchCamera: store.canSwitchCamera
                        )

                        ExperimentSidePanel(
                            layout: .portrait,
                            isExpanded: $isSidePanelExpanded
                        ) {
                            SessionTimerView(store: timerStore, isPortrait: true)
                        }
                        .ignoresSafeArea()
                        .frame(height: isSidePanelExpanded ? 398 : 83)
                        .anchorPreference(key: CameraPreviewAnchorKey.self, value: .bounds) { $0 }
                    }
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
    ) {}
}
