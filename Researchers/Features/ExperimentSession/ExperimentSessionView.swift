//
//  ExperimentSessionView.swift
//  Researchers
//
//  Created by 정홍섭 on 10/25/26.
//

import ComposableArchitecture
import LabcordiOS
import SwiftUI

struct ExperimentSessionView: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @State private var isSidePanelExpanded = true
    @State private var isGestureGuidePresented = false

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
                    isSidePanelExpanded: $isSidePanelExpanded,
                    store: captureStore,
                    timerStore: timerStore,
                    sessionStore: store,
                    onShowGestureGuide: { isGestureGuidePresented = true }
                )
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
                            if case let .recording(startedAt) = captureStore.videoPhase {
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
        .navigationBarBackButtonHidden()
        .overlay {
            if let data = captureStore.capturedPhotoData {
                CapturedPhotoView(
                    photoData: data,
                    isSaving: captureStore.photo.isSaving,
                    onRetake: { captureStore.send(.photo(.retakeRequested)) },
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
                    onRetake: { captureStore.send(.video(.retakeRequested)) },
                    onSave: { captureStore.send(.video(.saveRequested)) },
                    onPlaybackFinished: { captureStore.send(.video(.playbackFinished(recordID))) }
                )
                .id(url)
            }
        }
        .overlay {
            if voiceStore.phase != .hidden {
                VoiceRecordingView(store: voiceStore)
            }
        }
        .overlay {
            if !store.isReady {
                ExperimentSetupView()
                    .task(id: store.permissionRequestGeneration) {
                        try? await Task.sleep(for: .milliseconds(200))
                        guard !Task.isCancelled else { return }
                        store.send(.permissions(.request))
                    }
            }
        }
        .modifier(PauseOverlay(store: store))
        .overlay {
            if isGestureGuidePresented {
                ExperimentGestureGuideView {
                    isGestureGuidePresented = false
                }
            }
        }
        .task {
            await store.send(.loadDetail).finish()
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
        .alert(
            store.permissions.issue == .settingsUnavailable ? "설정 열기 실패" : "권한 안내",
            isPresented: Binding(
                get: { store.permissions.issue != nil },
                set: { if !$0 { store.send(.permissions(.issueDismissed)) } }
            )
        ) {
            if store.permissions.issue?.canOpenSettings == true {
                Button("설정 열기") {
                    store.send(.permissions(.openSettingsTapped))
                }
            }
            Button("확인", role: .cancel) {
                store.send(.permissions(.issueDismissed))
            }
        } message: {
            Text(store.permissions.issue?.message ?? "")
        }
        .alert(
            "카메라 오류",
            isPresented: Binding(
                get: { captureStore.cameraErrorMessage != nil },
                set: { if !$0 { captureStore.send(.cameraErrorDismissed) } }
            )
        ) {
            Button("확인", role: .cancel) {
                captureStore.send(.cameraErrorDismissed)
            }
        } message: {
            Text(captureStore.cameraErrorMessage ?? "")
        }
        .modifier(DetailLoadFailureAlert(store: store))
        .alert(
            "음성 기록 오류",
            isPresented: Binding(
                get: { voiceStore.errorMessage != nil },
                set: { if !$0 { voiceStore.send(.errorDismissed) } }
            )
        ) {
            Button("확인", role: .cancel) {
                voiceStore.send(.errorDismissed)
            }
        } message: {
            Text(voiceStore.errorMessage ?? "")
        }
        .alert(
            "사진 저장 실패",
            isPresented: Binding(
                get: { captureStore.photo.saveError != nil },
                set: { if !$0 { captureStore.send(.photo(.saveErrorDismissed)) } }
            )
        ) {
            Button("다시 시도") {
                captureStore.send(.photo(.saveRequested))
            }
            Button("닫기", role: .cancel) {
                captureStore.send(.photo(.saveErrorDismissed))
            }
        } message: {
            Text(captureStore.photo.saveError ?? "사진을 저장하지 못했습니다.")
        }
        .alert(
            "영상 저장 실패",
            isPresented: Binding(
                get: { captureStore.video.saveError != nil },
                set: { if !$0 { captureStore.send(.video(.saveErrorDismissed)) } }
            )
        ) {
            Button("다시 시도") {
                captureStore.send(.video(.saveRequested))
            }
            Button("닫기", role: .cancel) {
                captureStore.send(.video(.saveErrorDismissed))
            }
        } message: {
            Text(captureStore.video.saveError ?? "영상을 저장하지 못했습니다.")
        }
        .alert(
            "타이머 저장 실패",
            isPresented: Binding(
                get: { timerStore.saveFailed },
                set: { _ in }
            )
        ) {
            Button("다시 시도") {
                timerStore.send(.retrySaveTapped)
            }
        } message: {
            Text("타이머 기록을 저장하지 못했습니다.")
        }
    }

    private func previewFrame(anchor: Anchor<CGRect>?, geometry: GeometryProxy) -> CGRect {
        let fullFrame = CGRect(origin: .zero, size: geometry.size)
        guard let anchor else { return fullFrame }

        let anchoredFrame = geometry[anchor]
        if verticalSizeClass == .compact {
            return anchoredFrame
        }

        let previewOverlap: CGFloat = 50 + (isSidePanelExpanded ? 0 : 30)
        return CGRect(
            x: 0,
            y: 0,
            width: geometry.size.width,
            height: min(geometry.size.height, max(0, anchoredFrame.minY + previewOverlap))
        )
    }
}

private struct PauseOverlay: ViewModifier {
    let store: StoreOf<ExperimentSessionFeature>

    func body(content: Content) -> some View {
        content.overlay {
            if store.isPausePresented {
                ExperimentPauseView(
                    store: store.scope(state: \.pause, action: \.pause),
                    timerStore: store.scope(state: \.timer, action: \.timer),
                    canCloseSession: store.canCloseSession
                )
            }
        }
    }
}

private struct DetailLoadFailureAlert: ViewModifier {
    let store: StoreOf<ExperimentSessionFeature>

    func body(content: Content) -> some View {
        content.alert("실험 정보를 불러오지 못했어요", isPresented: Binding(
            get: { store.detailLoadFailed },
            set: { if !$0 { store.send(.dismissDetailLoadFailure) } }
        )) {
            Button("다시 시도") { store.send(.loadDetail) }
            Button("닫기", role: .cancel) { store.send(.dismissDetailLoadFailure) }
        } message: {
            Text("실험 정보를 불러온 뒤 녹음할 수 있어요.")
        }
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
