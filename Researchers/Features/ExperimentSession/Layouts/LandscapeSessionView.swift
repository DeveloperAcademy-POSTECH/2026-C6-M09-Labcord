//
//  LandscapeSessionView.swift
//  Researchers
//
//  Created by 정홍섭 on 10/25/26.
//

import ComposableArchitecture
import LabcordDesignSystem
import LabcordShared
import SwiftUI

struct LandscapeSessionView: View {
    let sessionStore: StoreOf<ExperimentSessionFeature>

    private var areRecordButtonsDisabled: Bool {
        sessionStore.voice.phase != .hidden
            || sessionStore.capture.previewConnector == nil
            || sessionStore.capture.isCameraSwitching
            || sessionStore.capture.isPhotoCaptureScheduled
            || sessionStore.capture.isCapturingPhoto
            || sessionStore.capture.capturedPhotoData != nil
            || sessionStore.capture.videoPhase != .idle
    }

    private var extraSpacerWidth: CGFloat {
        sessionStore.isSidePanelExpanded ? 0 : 32
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .ignoresSafeArea()

            HStack(spacing: 0) {
                VStack {
                    HStack {
                        HeaderView(store: sessionStore)
                            .padding(.top, 20)
                            .padding(.leading, 3)

                        ExperimentRecordButtonsView(
                            store: sessionStore.scope(state: \.capture, action: \.capture),
                            isDisabled: areRecordButtonsDisabled
                        )
                    }
                    .padding(.top, 10)
                    .padding(.trailing, -extraSpacerWidth)

                    Spacer()

                    ExperimentSettingButtonsView(
                        onShowGestureGuide: { sessionStore.send(.gestureGuidePresented(true)) },
                        onShowRunningTimers: {
                            sessionStore.send(.timer(.timerTabSelected(.active)))
                            sessionStore.send(.sidePanelExpanded(true))
                        },
                        onSwitchCamera: { sessionStore.send(.capture(.cameraSwitchRequested)) },
                        onRotate: { SessionOrientation.toggle() },
                        showsRunningTimerButton: !sessionStore.isSidePanelExpanded
                            && sessionStore.timer.timerCollection.hasRunningTimers,
                        canSwitchCamera: sessionStore.capture.canSwitchCamera
                    )
                    .padding(.trailing, -extraSpacerWidth)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 20)

                ExperimentSidePanel(
                    layout: .landscape,
                    isExpanded: Binding(
                        get: { sessionStore.isSidePanelExpanded },
                        set: { sessionStore.send(.sidePanelExpanded($0)) }
                    )
                )
                .fixedSize(horizontal: true, vertical: false)
            }
            .ignoresSafeArea(.container, edges: [.bottom, .trailing])
        }
    }
}

#Preview {
    LandscapeSessionView(
        sessionStore: Store(
            initialState: ExperimentSessionFeature.State(experimentID: UUID())
        ) {
            ExperimentSessionFeature()
        }
    )
}
