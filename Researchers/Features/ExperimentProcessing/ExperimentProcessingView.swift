//
//  ExperimentProcessingView.swift
//  Researchers
//
//  Created by 정홍섭 on 11/1/26.
//

import LabcordDesignSystem
import SwiftUI

struct ExperimentProcessingView: View {
    var body: some View {
        VStack(spacing: LayoutTokens.spacing12) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.green)

            Text("실험 내용을 정리하고 있어요.")
                .typography(Typography.title3SemiBold)
                .foregroundStyle(Color("General/Label/Primary"))
        }
    }
}

#Preview {
    ExperimentProcessingView()
}
