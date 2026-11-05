//
//  ExperimentSetupView.swift
//  Researchers
//
//  Created by 정홍섭 on 10/24/26.
//

import LabcordDesignSystem
import SwiftUI

struct ExperimentSetupView: View {
    var body: some View {
        ZStack {
            Color("Experiment/Background/Primary")

            VStack(spacing: 8) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.large)
                    .tint(Color("Experiment/Label/Brand"))

                VStack(spacing: 7) {
                    Text("실험할 위치에 iPhone을 놓아주세요")
                        .typography(Typography.title3SemiBold)
                        .foregroundStyle(Color("Experiment/Label/Primary"))

                    Text("카메라가 준비되면 자동으로 시작돼요")
                        .typography(Typography.body)
                        .foregroundStyle(Color("Experiment/Label/Secondary"))
                }
            }
        }
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
    }
}

#Preview {
    ExperimentSetupView()
}
