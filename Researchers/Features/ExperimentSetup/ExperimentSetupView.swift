//
//  ExperimentSetupView.swift
//  Researchers
//
//  Created by 정홍섭 on 10/24/26.
//

import SwiftUI

struct ExperimentSetupView: View {
    var failure: SessionSetupFailure?
    var canOpenSettings = false
    var onLeave: () -> Void = {}
    var onOpenSettings: () -> Void = {}
    var onRetry: () -> Void = {}

    var body: some View {
        ZStack {
            Color(.black)

            VStack(spacing: 20) {
                if failure == nil {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.large)
                        .tint(.white)
                }

                VStack(spacing: 7) {
                    Text("실험할 위치\niPhone을 놓아주세요")
                        .font(.title)
                        .multilineTextAlignment(.center)

                    Text(message)
                        .multilineTextAlignment(.center)
                }

                if let failure {
                    failureActions(failure)
                }

                Button("홈으로", action: onLeave)
                    .buttonStyle(.bordered)
                    .accessibilityLabel("홈으로")
            }
            .padding(24)
        }
        .ignoresSafeArea()
        .foregroundStyle(.white)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var message: String {
        switch failure {
        case let .permission(message), let .camera(message):
            return message
        case nil:
            return "준비가 끝나면 실험이 시작돼요"
        }
    }

    @ViewBuilder
    private func failureActions(_ failure: SessionSetupFailure) -> some View {
        switch failure {
        case .permission:
            if canOpenSettings {
                Button("설정 열기", action: onOpenSettings)
                    .buttonStyle(.borderedProminent)
            }
        case .camera:
            Button("다시 시도", action: onRetry)
                .buttonStyle(.borderedProminent)
        }
    }
}

#Preview {
    ExperimentSetupView()
}
