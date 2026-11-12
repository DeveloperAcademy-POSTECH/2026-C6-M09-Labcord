//
//  LandscapeSessionView.swift
//  Researchers
//
//  Created by 정홍섭 on 10/25/26.
//

import ComposableArchitecture
import SwiftUI

struct LandscapeSessionView: View {
    let sessionStore: StoreOf<ExperimentSessionFeature>

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .ignoresSafeArea()

            HeaderView(store: sessionStore)
                .padding(.top, 20)
                .padding(.leading, 3)
        }
    }
}

#Preview {
    LandscapeSessionView(
        sessionStore: Store(
            initialState: ExperimentSessionFeature.State(experimentID: UUID())
        ) {
            ExperimentSessionFeature()
        }
    )
}
