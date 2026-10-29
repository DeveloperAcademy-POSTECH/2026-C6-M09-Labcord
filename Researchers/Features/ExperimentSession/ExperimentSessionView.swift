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

    let store: StoreOf<ExperimentSessionFeature>
    @State private var timerStore = Store(initialState: SessionTimerFeature.State()) {
        SessionTimerFeature()
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
                    store: captureStore,
                    timerStore: timerStore,
                    sessionStore: store
                )
            }
        }
        .backgroundPreferenceValue(CameraPreviewAnchorKey.self) { anchor in
            GeometryReader { geometry in
                if let connector = captureStore.previewConnector {
                    let frame = verticalSizeClass == .compact
                        ? anchor.map { geometry[$0] } ?? CGRect(origin: .zero, size: geometry.size)
                        : CGRect(origin: .zero, size: geometry.size)
                    CameraPreviewView(connector: connector)
                        .frame(width: frame.width, height: frame.height)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: verticalSizeClass == .compact ? 15 : 0
                            )
                        )
                        .overlay(alignment: .topLeading) {
                            if case let .recording(startedAt) = captureStore.videoPhase {
                                VideoRecordingIndicator(startedAt: startedAt)
                                    .padding(.leading, 16)
                                    .padding(.top, verticalSizeClass == .compact ? 16 : 130)
                            }
                        }
                        .position(x: frame.midX, y: frame.midY)
                        .allowsHitTesting(false)
                }
            }
            .ignoresSafeArea()
        }
        .navigationBarBackButtonHidden()
        .overlay {
            if let data = captureStore.capturedPhotoData {
                CapturedPhotoView(photoData: data) {
                    captureStore.send(.retakeRequested)
                }
            }
        }
        .overlay {
            if case let .preview(url) = captureStore.videoPhase {
                CapturedVideoView(videoURL: url) {
                    captureStore.send(.videoRetakeRequested)
                }
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
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            captureStore.send(.cameraViewAppeared)
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            if !store.isReturningHome {
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
    }
}

#Preview {
    ExperimentSessionView(store: Store(initialState: ExperimentSessionFeature.State()) {
        ExperimentSessionFeature()
    })
}
