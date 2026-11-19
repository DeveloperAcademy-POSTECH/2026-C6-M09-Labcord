//
//  ExperimentProcessingView.swift
//  Researchers
//
//  Created by 정홍섭 on 11/1/26.
//

import LabcordDesignSystem
import SwiftUI

struct ExperimentProcessingView: View {
    let isOpenedFromHome: Bool
    @State private var isTakingLonger = false

    private var message: String {
        isOpenedFromHome ? "실험 내용을 불러오고 있어요." : "실험 내용을 정리하고 있어요."
    }

    var body: some View {
        VStack(spacing: LayoutTokens.spacing12) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(Color("General/Brand/Primary"))

            Text(message)
                .typography(Typography.title3SemiBold)
                .foregroundStyle(Color("General/Label/Primary"))

            if isTakingLonger {
                Text("실험과 기록을 확인하는 데 시간이 조금 더 걸리고 있어요.")
                    .foregroundStyle(Color("General/Label/Secondary"))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(LayoutTokens.spacing24)
        .accessibilityElement(children: .combine)
        .task {
            do {
                try await Task.sleep(for: .seconds(5))
                isTakingLonger = true
            } catch {}
        }
    }
}

#Preview {
    ExperimentProcessingView(isOpenedFromHome: false)
}
