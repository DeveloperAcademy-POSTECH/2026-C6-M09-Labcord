//
//  ExperimentResultView.swift
//  Researchers
//
//  Created by 정홍섭 on 10/29/26.
//

import ComposableArchitecture
import SwiftUI

struct ExperimentResultView: View {
    let store: StoreOf<ExperimentResultFeature>

    var body: some View {
        VStack(spacing: 20) {
            Text("기록 종료 화면")

            Button {
                store.send(.homeTapped)
            } label: {
                Text("홈으로 이동")
            }
        }
    }
}

#Preview {
    ExperimentResultView(
        store: Store(
            initialState: ExperimentResultFeature.State()
        ) {
            ExperimentResultFeature()
        }
    )
}
