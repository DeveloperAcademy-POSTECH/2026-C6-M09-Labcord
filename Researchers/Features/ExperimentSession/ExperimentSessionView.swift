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

    @State private var store = Store(initialState: ExperimentSessionFeature.State()) {
        ExperimentSessionFeature()
    }
    @State private var timerStore = Store(initialState: SessionTimerFeature.State()) {
        SessionTimerFeature()
    }

    var body: some View {
        Group {
            if verticalSizeClass == .compact {
                LandscapeSessionView(store: store, timerStore: timerStore)
            } else {
                PortraitSessionView(store: store, timerStore: timerStore)
            }
        }
        .backgroundPreferenceValue(CameraPreviewAnchorKey.self) { anchor in
            GeometryReader { geometry in
                if let connector = store.previewConnector {
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
                            if case let .recording(startedAt) = store.videoPhase {
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
        .overlay {
            if let data = store.capturedPhotoData {
                CapturedPhotoView(photoData: data) {
                    store.send(.retakeRequested)
                }
            }
        }
        .overlay {
            if case let .preview(url) = store.videoPhase {
                CapturedVideoView(videoURL: url) {
                    store.send(.videoRetakeRequested)
                }
            }
        }
        .overlay {
            if store.voice.phase != .hidden {
                VoiceRecordingView(store: store.scope(state: \.voice, action: \.voice))
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            store.send(.cameraViewAppeared)
            store.send(.permissions(.request))
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            store.send(.cameraViewDisappeared)
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
                get: { store.cameraErrorMessage != nil },
                set: { if !$0 { store.send(.cameraErrorDismissed) } }
            )
        ) {
            Button("확인", role: .cancel) {
                store.send(.cameraErrorDismissed)
            }
        } message: {
            Text(store.cameraErrorMessage ?? "")
        }
        .alert(
            "음성 기록 오류",
            isPresented: Binding(
                get: { store.voice.errorMessage != nil },
                set: { if !$0 { store.send(.voice(.errorDismissed)) } }
            )
        ) {
            Button("확인", role: .cancel) {
                store.send(.voice(.errorDismissed))
            }
        } message: {
            Text(store.voice.errorMessage ?? "")
        }
    }
}

struct CameraPreviewAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

#Preview {
    ExperimentSessionView()
}
