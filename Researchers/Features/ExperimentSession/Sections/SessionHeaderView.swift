//
//  SessionHeaderView.swift
//  Researchers
//
//  Created by 정홍섭 on 10/25/26.
//

import ComposableArchitecture
import SwiftUI

struct SessionHeaderView: View {
    let store: StoreOf<ExperimentSessionFeature>

    var body: some View {
        HStack(spacing: 19) {
            Text("촉매 반응 조건 비교 실험 A")
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
    SessionHeaderView(store: Store(initialState: ExperimentSessionFeature.State()) {
        ExperimentSessionFeature()
    })
}
