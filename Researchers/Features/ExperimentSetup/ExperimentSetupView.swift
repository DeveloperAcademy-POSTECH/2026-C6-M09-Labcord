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
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.large)
                    .tint(.white)

                VStack(spacing: 7) {
                    Text("실험할 위치\n iPhone을 놓아주세요")
                        .font(.title)
                        .multilineTextAlignment(.center)

                    Text("카메라가 준비되면 자동으로 시작돼요")
                }
            }
        }
        .ignoresSafeArea()
        .foregroundStyle(.white)
        .toolbar(.hidden, for: .navigationBar)
    }
}

#Preview {
    ExperimentSetupView()
}
