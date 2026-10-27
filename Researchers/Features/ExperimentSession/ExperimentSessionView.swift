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

    var body: some View {
        Group {
            if verticalSizeClass == .compact {
                LandscapeSessionView(store: store)
            } else {
                PortraitSessionView(store: store)
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
