//
//  ExperimentProcessingView.swift
//  Researchers
//
//  Created by 정홍섭 on 11/1/26.
//

import SwiftUI

struct ExperimentProcessingView: View {
    var body: some View {
        VStack {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.large)
                .tint(.green)

            Text("실험 내용을 정리하고 있어요.")
        }
    }
}

#Preview {
    ExperimentProcessingView()
}
