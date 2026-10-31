//
//  SessionHeaderView.swift
//  Researchers
//
//  Created by 정홍섭 on 10/25/26.
//

import ComposableArchitecture
import LabcordiOS
import SwiftUI

struct SessionHeaderView: View {
    let store: StoreOf<ExperimentSessionFeature>

    var body: some View {
        HStack(spacing: 19) {
            Text(store.detail?.title ?? "불러오는 중...")
                .lineLimit(1)
                .font(.title2.bold())

            Spacer()

            Button {
                store.send(.stopTapped)
            } label: {
                Image(systemName: "stop.fill")
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)

            Button {
                store.send(.returnHomeTapped)
            } label: {
                Image(systemName: "pause.fill")
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
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
}
