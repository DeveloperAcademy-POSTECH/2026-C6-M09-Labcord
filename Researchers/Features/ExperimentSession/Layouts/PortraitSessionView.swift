//
//  PortraitSessionView.swift
//  Researchers
//
//  Created by 정홍섭 on 10/25/26.
//

import ComposableArchitecture
import SwiftUI

struct PortraitSessionView: View {
    let store: StoreOf<ExperimentSessionFeature>

    var body: some View {
        GeometryReader { geo in
            let screenHeight = geo.size.height
                + geo.safeAreaInsets.top
                + geo.safeAreaInsets.bottom

            ZStack {
                Rectangle()
                    .ignoresSafeArea()
                    .foregroundStyle(.gray)

                VStack {
                    SessionHeaderView()
                        .padding(16)

                    Spacer()
                }

                PortraitSessionDockView(
                    store: store,
                    compactHeight: screenHeight * 0.127,
                    expandedHeight: screenHeight * 0.3890160183,
                    bottomInset: geo.safeAreaInsets.bottom
                )
            }
            .foregroundStyle(.white)
        }
    }
}

#Preview {
    PortraitSessionView(
        store: Store(
            initialState: ExperimentSessionFeature.State()
        ) {
            ExperimentSessionFeature()
        }
    )
}
