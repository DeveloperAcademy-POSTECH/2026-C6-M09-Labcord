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
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .background(.black)
        .alert(
            "설정 열기 실패",
            isPresented: Binding(
                get: { store.cameraPermission.openSettingsErrorMessage != nil },
                set: { if !$0 { store.send(.cameraPermission(.openSettingsErrorDismissed)) } }
            )
        ) {
            Button("확인", role: .cancel) {
                store.send(.cameraPermission(.openSettingsErrorDismissed))
            }
        } message: {
            Text(store.cameraPermission.openSettingsErrorMessage ?? "")
        }
        .task {
            store.send(.cameraPermission(.request))
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
