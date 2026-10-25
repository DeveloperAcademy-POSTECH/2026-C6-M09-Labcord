//
//  PortraitSessionView.swift
//  Researchers
//
//  Created by 정홍섭 on 10/25/26.
//

import SwiftUI
import ComposableArchitecture

struct PortraitSessionView: View {
    let store: StoreOf<ExperimentSessionFeature>
    
    @State private var showTimerSheet = true
    @State private var selectedTimerDetent: PresentationDetent =
        .fraction(0.3890160183)
    
    var body: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .ignoresSafeArea()
                .foregroundStyle(.gray)
            
            SessionHeaderView()
                .padding(16)
        }
        .foregroundStyle(.white)
        .sheet(isPresented: $showTimerSheet) {
            GeometryReader { _ in
                SessionTimerView(store: store)
                    .padding(.horizontal, 16)
                    .padding(.top, 40)
            }
            .presentationDetents(
                [.fraction(0.127), .fraction(0.3890160183)],
                selection: $selectedTimerDetent
            )
            .presentationBackgroundInteraction(.enabled)
            .presentationDragIndicator(.visible)
            .interactiveDismissDisabled()
            .presentationBackground(.black)
            .preferredColorScheme(.dark)
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
