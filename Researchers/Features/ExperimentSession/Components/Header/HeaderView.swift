//
//  HeaderView.swift
//  Researchers
//
//  Created by 정홍섭 on 10/25/26.
//

import ComposableArchitecture
import LabcordDesignSystem
import LabcordiOS
import SwiftUI

struct HeaderView: View {
    let store: StoreOf<ExperimentSessionFeature>

    var body: some View {
        HStack(spacing: 16) {
            Button {
                store.send(.pauseTapped)
            } label: {
                Image(labcordIcon: .pause)
                    .foregroundStyle(Color("Experiment/Label/Primary"))
            }
            .buttonStyle(.labcordIcon(.neutral, size: .large))
            .accessibilityLabel("실험 일시정지")
            .background(
                VisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
            )
            .cornerRadius(LayoutTokens.radiusFull)

            Text(store.detail?.title ?? "불러오는 중...")
                .lineLimit(1)
                .typography(Typography.headline)
                .foregroundStyle(Color("Experiment/Label/Primary"))

            Spacer()
        }
    }
}

#Preview {
    HeaderView(
        store: Store(
            initialState: ExperimentSessionFeature.State(experimentID: UUID())
        ) {
            ExperimentSessionFeature()
        }
    )
    .background(.black)
}
