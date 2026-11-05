//
//  SessionHeaderView.swift
//  Researchers
//
//  Created by 정홍섭 on 10/25/26.
//

import ComposableArchitecture
import LabcordDesignSystem
import LabcordiOS
import SwiftUI

struct SessionHeaderView: View {
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

            Text(store.detail?.title ?? "불러오는 중...")
                .lineLimit(1)
                .typography(Typography.headline)
                .foregroundStyle(Color("Experiment/Label/Primary"))

            Spacer()
        }
    }
}

#Preview {
    SessionHeaderView(
        store: Store(
            initialState: ExperimentSessionFeature.State(experimentID: UUID())
        ) {
            ExperimentSessionFeature()
        }
    )
    .background(.black)
}
