//
//  SessionCaptureView.swift
//  Researchers
//
//  Created by 정홍섭 on 10/25/26.
//

import ComposableArchitecture
import SwiftUI

struct SessionCaptureView: View {
    let store: StoreOf<ExperimentSessionFeature>

    var body: some View {
        VStack(spacing: 20) {
            Color.clear
                .frame(width: 401, height: 215)
                .anchorPreference(key: CameraPreviewAnchorKey.self, value: .bounds) { $0 }
                .overlay {
                    VStack {
                        Spacer()

                        HStack {
                            Button {
                                store.send(.cameraSwitchRequested)
                            } label: {
                                Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                                    .font(.body)
                                    .frame(width: 40, height: 40)
                            }
                            .foregroundStyle(.white)
                            .buttonStyle(.borderedProminent)
                            .buttonBorderShape(.circle)
                            .tint(.black.opacity(0.5))
                            .disabled(store.previewConnector == nil || store.isCameraSwitching)

                            Spacer()
                        }
                        .padding(16)
                    }
                }

            HStack(spacing: 24) {
                Button {

                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "record.circle")
                        Text("음성 기록")
                    }
                    .font(.body)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                }
                .frame(maxWidth: 118)
                .foregroundStyle(.black)
                .buttonStyle(.borderedProminent)
                .tint(.white)

                Button {

                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "camera.viewfinder")
                        Text("장면 캡쳐")
                    }
                    .font(.body)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                }
                .frame(maxWidth: 118)
                .foregroundStyle(.black)
                .buttonStyle(.borderedProminent)
                .tint(.white)

                Button {

                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "video.fill")
                        Text("영상 기록")
                    }
                    .font(.body)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                }
                .frame(maxWidth: 118)
                .foregroundStyle(.black)
                .buttonStyle(.borderedProminent)
                .tint(.white)
            }
        }
        .frame(minWidth: 401)
    }
}

#Preview {
    SessionCaptureView(store: Store(initialState: ExperimentSessionFeature.State()) {
        ExperimentSessionFeature()
    })
}
