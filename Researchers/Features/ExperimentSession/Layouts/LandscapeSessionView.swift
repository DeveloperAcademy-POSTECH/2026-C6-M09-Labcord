//
//  LandscapeSessionView.swift
//  Researchers
//
//  Created by 정홍섭 on 10/25/26.
//

import ComposableArchitecture
import LabcordDesignSystem
import LabcordiOS
import SwiftUI
import LabcordShared

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

    private var recordButtons: some View {
        ExperimentRecordButtonsView(
            store: sessionStore.scope(state: \.capture, action: \.capture),
            isDisabled: areRecordButtonsDisabled
        )
    }

    private var cameraPreview: some View {
        GeometryReader { geometry in
            if let connector = sessionStore.capture.previewConnector {
                CameraPreviewView(connector: connector, showsHandOverlay: false)
                    .frame(width: geometry.size.width + 50, height: geometry.size.height)
                    .frame(width: geometry.size.width, alignment: .leading)
                    .overlay {
                        if let endsAt = sessionStore.capture.photo.countdownEndAt {
                            PhotoCaptureCountdownView(endsAt: endsAt)
                        }
                    }
                    .transaction { $0.disablesAnimations = true }
                    .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea(.container, edges: [.top, .bottom, .leading])
    }

    var body: some View {
        GeometryReader { geometry in
            let trailingInset = max(LayoutTokens.spacing16, geometry.safeAreaInsets.trailing)

            HStack(spacing: 0) {
                controls
                sidePanel(trailingInset: trailingInset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.container, edges: [.bottom, .trailing])
        }
    }

    private var controls: some View {
        VStack {
            HStack {
                HeaderView(store: sessionStore)
                    .padding(.top, 20)
                    .padding(.leading, 3)

                if !sessionStore.isSidePanelExpanded {
                    recordButtons
                }
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
        .background { cameraPreview }
    }

    private func sidePanel(trailingInset: CGFloat) -> some View {
        ExperimentSidePanel(
            layout: .landscape,
            isExpanded: Binding(
                get: { sessionStore.isSidePanelExpanded },
                set: { sessionStore.send(.sidePanelExpanded($0)) }
            ),
            landscapeTrailingInset: trailingInset
        ) {
            SessionTimerView(store: sessionStore.scope(state: \.timer, action: \.timer))
                .foregroundStyle(.white)
        }
        .fixedSize(horizontal: true, vertical: false)
        .overlay(alignment: .topTrailing) {
            if sessionStore.isSidePanelExpanded {
                recordButtons
                    .padding(.top, 8.9)
                    .padding(.trailing, trailingInset)
            }
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
