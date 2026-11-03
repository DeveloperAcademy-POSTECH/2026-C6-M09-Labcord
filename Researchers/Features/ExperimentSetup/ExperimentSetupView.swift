//
//  ExperimentSetupView.swift
//  Researchers
//
//  Created by 정홍섭 on 10/24/26.
//

import LabcordDesignSystem
import SwiftUI

struct ExperimentSetupView: View {
    var canContinueWithoutCamera = false
    var onRetry: (() -> Void)?
    var onContinueWithoutCamera: (() -> Void)?

    var body: some View {
        ZStack {
            Color(.black)

            VStack(spacing: 20) {
                if !canContinueWithoutCamera {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.large)
                        .tint(.white)
                }

                VStack(spacing: 7) {
                    Text(canContinueWithoutCamera
                         ? "카메라를 사용할 수 없어요" : "실험할 위치\n iPhone을 놓아주세요")
                        .font(.title)
                        .multilineTextAlignment(.center)

                    Text(canContinueWithoutCamera
                         ? "사진·영상과 손 제스처를 제외하고 계속할 수 있어요."
                         : "카메라가 준비되면 자동으로 시작돼요")
                        .multilineTextAlignment(.center)
                }

                if canContinueWithoutCamera {
                    if let onRetry {
                        Button("카메라 다시 시도", action: onRetry)
                            .buttonStyle(.labcord(.secondary))
                    }
                    if let onContinueWithoutCamera {
                        Button("음성·타이머만 사용", action: onContinueWithoutCamera)
                            .buttonStyle(.labcord(.primary))
                    }
                }
            }
            .padding(24)
        }
        .ignoresSafeArea()
        .foregroundStyle(.white)
        .toolbar(.hidden, for: .navigationBar)
    }
}

#Preview {
    ExperimentSetupView()
}
