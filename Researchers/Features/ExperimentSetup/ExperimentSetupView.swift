//
//  ExperimentSetupView.swift
//  Researchers
//
//  Created by 정홍섭 on 10/24/26.
//

import SwiftUI

struct ExperimentSetupView: View {
    var body: some View {
        ZStack {
            Color(.black)

            VStack(spacing: 20) {
                Image(systemName: "iphone")
                    .font(.system(size: 100))

                Text("잠시후 기록 대기 모드로 전환됩니다.")
                    .font(.headline)

                Text("실험 기록은 계속 작동하고 있으며,\n언제든 기록할 수 있어요.")
                    .multilineTextAlignment(.center)
                    .font(.subheadline)

                Button {
                    // 화면 이동 코드
                } label: {
                    Text("시작하기")
                        .frame(maxWidth: .infinity)
                        .frame(height: 49)
                }
                .frame(maxWidth: 304)
                .foregroundStyle(.black)
                .buttonStyle(.borderedProminent)
                .tint(.white)
            }
        }
        .ignoresSafeArea()
        .foregroundStyle(.white)
    }
}

#Preview {
    ExperimentSetupView()
}
