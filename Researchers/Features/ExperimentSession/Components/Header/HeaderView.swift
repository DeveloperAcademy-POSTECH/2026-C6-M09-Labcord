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
            ExperimentControlButton {
                store.send(.pauseTapped)
            } icon: {
                Image(labcordIcon: .pause)
            }
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
