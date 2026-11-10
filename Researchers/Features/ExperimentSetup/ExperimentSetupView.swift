//
//  ExperimentSetupView.swift
//  Researchers
//
//  Created by 정홍섭 on 10/24/26.
//

import LabcordDesignSystem
import LabcordiOS
import SwiftUI

extension ExperimentSessionFeature.State {
    var setupFailureMessage: String? {
        if cameraPreparationTimedOut {
            return "카메라를 준비하지 못했어요. 다시 시도해주세요."
        }
        if let message = capture.cameraErrorMessage, capture.previewConnector == nil {
            return message
        }
        return nil
    }
}

struct ExperimentSetupView: View {
    var failureMessage: String?
    var onRetry: () -> Void = {}

    var body: some View {
        ZStack {
            Color("Experiment/Background/Primary")

            VStack(spacing: 8) {
                if failureMessage == nil {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.large)
                        .tint(Color("Experiment/Label/Brand"))
                }

                VStack(spacing: 7) {
                    Text("실험할 위치에 iPhone을 놓아주세요")
                        .typography(Typography.title3SemiBold)
                        .foregroundStyle(Color("Experiment/Label/Primary"))
                        .multilineTextAlignment(.center)

                    Text(failureMessage ?? "카메라가 준비되면 자동으로 시작돼요")
                        .typography(Typography.body)
                        .foregroundStyle(Color("Experiment/Label/Secondary"))
                        .multilineTextAlignment(.center)
                }

                if failureMessage != nil {
                    Button("다시 시도", action: onRetry)
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
        }
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
    }
}

#Preview {
    ExperimentSetupView(failureMessage: nil)
}
