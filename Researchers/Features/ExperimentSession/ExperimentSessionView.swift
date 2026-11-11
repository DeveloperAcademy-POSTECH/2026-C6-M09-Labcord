//
//  ExperimentSessionView.swift
//  Researchers
//
//  Created by 정홍섭 on 10/25/26.
//

import ComposableArchitecture
import LabcordDesignSystem
import LabcordiOS
import SwiftUI

struct ExperimentSessionView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @State private var voiceToast: VoiceToastPresentation?
    let store: StoreOf<ExperimentSessionFeature>
    private var timerStore: StoreOf<SessionTimerFeature> {
        store.scope(state: \.timer, action: \.timer)
    }
    private var captureStore: StoreOf<CameraCaptureFeature> {
        store.scope(state: \.capture, action: \.capture)
    }
    private var voiceStore: StoreOf<VoiceRecordingFeature> {
        store.scope(state: \.voice, action: \.voice)
    }
    private var videoStore: StoreOf<VideoFeature> {
        captureStore.scope(state: \.video, action: \.video)
    }
    private var isPortraitVoiceActivityVisible: Bool {
        verticalSizeClass != .compact
            && voiceStore.saveError == nil
            && (voiceStore.phase != .hidden || voiceStore.hasRecordingFailure)
    }
    private var isVideoActivityVisible: Bool {
        guard verticalSizeClass != .compact else { return false }
        switch videoStore.phase {
        case .starting, .recording: return true
        case .idle, .preview: return false
        }
    }

    var body: some View {
        Group {
            if verticalSizeClass == .compact {
                LandscapeSessionView(
                    store: captureStore,
                    timerStore: timerStore,
                    sessionStore: store
                )
            } else {
                PortraitSessionView(
                    isSidePanelExpanded: Binding(
                        get: { store.isSidePanelExpanded },
                        set: { store.send(.sidePanelExpanded($0)) }
                    ),
                    store: captureStore,
                    timerStore: timerStore,
                    sessionStore: store
                ) { store.send(.gestureGuidePresented(true)) }
            }
        }
        .backgroundPreferenceValue(CameraPreviewAnchorKey.self) { anchor in
            GeometryReader { geometry in
                if let connector = captureStore.previewConnector {
                    let frame = previewFrame(anchor: anchor, geometry: geometry)
                    CameraPreviewView(connector: connector, showsHandOverlay: false)
                        .frame(width: frame.width, height: frame.height)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: verticalSizeClass == .compact ? 15 : 0
                            )
                        )
                        .overlay {
                            if let endsAt = captureStore.photo.countdownEndAt {
                                PhotoCaptureCountdownView(endsAt: endsAt)
                            }
                        }
                        .overlay(alignment: .topLeading) {
                            if verticalSizeClass == .compact,
                               case let .recording(startedAt) = captureStore.videoPhase {
                                VideoRecordingIndicator(startedAt: startedAt)
                                    .padding(.leading, 16)
                                    .padding(.top, verticalSizeClass == .compact ? 16 : 130)
                            }
                        }
                        .position(x: frame.midX, y: frame.midY)
                        .transaction { $0.disablesAnimations = true }
                        .allowsHitTesting(false)
                }
            }
            .ignoresSafeArea()
        }
        .overlay(alignment: .top) {
            WatchVoiceRecordingIndicator(experimentID: store.experimentID)
        }
        .navigationBarBackButtonHidden()
        .toolbarVisibility(
            isPortraitVoiceActivityVisible || isVideoActivityVisible
                ? .hidden : .automatic,
            for: .statusBar
        )
        .overlay {
            if let data = captureStore.capturedPhotoData {
                CapturedPhotoView(
                    photoData: data,
                    isSaving: captureStore.photo.isSaving,
                    onRetake: { captureStore.send(.photoRetakeAndCaptureRequested) },
                    onClose: { captureStore.send(.photo(.retakeRequested)) },
                    onSave: { captureStore.send(.photo(.saveRequested)) }
                )
            }
        }
        .overlay {
            if case let .preview(url) = captureStore.videoPhase,
               let recordID = captureStore.video.recordID {
                CapturedVideoView(
                    videoURL: url,
                    isSaving: captureStore.video.isSaving,
                    showAutoSaveMessage: captureStore.video.isAutoSavePending,
                    onRetake: { captureStore.send(.videoRetakeAndRecordRequested) },
                    onClose: { captureStore.send(.video(.cancelRequested)) },
                    onSave: { captureStore.send(.video(.saveRequested)) },
                    onPlaybackFinished: { captureStore.send(.video(.playbackFinished(recordID))) }
                )
                .id(url)
            }
        }
        .overlay {
            if verticalSizeClass == .compact {
                if voiceStore.phase != .hidden {
                    VoiceRecordingView(store: voiceStore)
                }
            } else if isPortraitVoiceActivityVisible {
                GeometryReader { geometry in
                    VoiceLiveActivityView(
                        store: voiceStore,
                        onRestart: { store.send(.voiceStartRequested) },
                        onFailureAutoDismiss: {
                            voiceToast = VoiceToastPresentation(kind: .recordingFailure)
                        },
                        availableWidth: geometry.size.width
                    )
                    .padding(.top, 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .ignoresSafeArea(.container, edges: .top)
                .transition(.opacity)
            } else if isVideoActivityVisible {
                GeometryReader { geometry in
                    VideoLiveActivityView(store: videoStore, availableWidth: geometry.size.width)
                        .id(videoStore.sessionID)
                        .padding(.top, 14)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .ignoresSafeArea(.container, edges: .top)
                .transition(.opacity)
            }
        }
        .animation(
            reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.08),
            value: isPortraitVoiceActivityVisible
        )
        .animation(
            reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.08),
            value: isVideoActivityVisible
        )
        .modifier(
            VoiceRecordToastOverlay(
                voiceStore: voiceStore,
                sessionStore: store,
                presentation: $voiceToast
            )
        )
        .overlay {
            if !store.isReady && !store.isRemotePreview {
                ExperimentSetupView(
                    failureMessage: store.setupFailureMessage
                ) { store.send(.setupRetryCameraTapped) }
                    .task(id: store.permissionRequestGeneration) {
                        try? await Task.sleep(for: .milliseconds(200))
                        guard !Task.isCancelled else { return }
                        store.send(.permissions(.request))
                    }
                    .task(id: "\(store.permissions.camera.status)-"
                          + "\(store.permissionRequestGeneration)") {
                        try? await Task.sleep(for: .seconds(15))
                        guard !Task.isCancelled else { return }
                        store.send(.cameraPreparationTimedOut)
                    }
            }
        }
        .overlay {
            if store.isRemotePreview {
                RemoteExperimentPreparation(store: store)
            }
        }
        .modifier(PauseOverlay(store: store))
        .overlay {
            if store.isGestureGuidePresented {
                ExperimentGestureGuideView {
                    store.send(.gestureGuidePresented(false))
                }
            }
        }
        .task(id: [store.isRemotePreview, store.isSetupReady]) {
            if store.isRemotePreview || store.isSetupReady {
                await store.send(.loadDetail).finish()
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            captureStore.send(.cameraViewAppeared)
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            if store.isReturningHome {
                captureStore.send(.video(.cancelRequested))
                voiceStore.send(.closeRequested)
            } else {
                captureStore.send(.cameraViewDisappeared)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                store.send(.appBecameActive)
            }
        }
        .background(.black)
        .modifier(SessionAlerts(store: store))
    }

    private func previewFrame(anchor: Anchor<CGRect>?, geometry: GeometryProxy) -> CGRect {
        let fullFrame = CGRect(origin: .zero, size: geometry.size)
        guard let anchor else { return fullFrame }

        let anchoredFrame = geometry[anchor]
        if verticalSizeClass == .compact {
            return anchoredFrame
        }

        let previewOverlap: CGFloat = 50 + (store.isSidePanelExpanded ? 0 : 30)
        return CGRect(
            x: 0,
            y: 0,
            width: geometry.size.width,
            height: min(geometry.size.height, max(0, anchoredFrame.minY + previewOverlap))
        )
    }

}

#Preview {
    ExperimentSessionView(
        store: Store(
            initialState: ExperimentSessionFeature.State(
                experimentID: UUID()
            )
        ) {
            ExperimentSessionFeature()
        }
    )
}
