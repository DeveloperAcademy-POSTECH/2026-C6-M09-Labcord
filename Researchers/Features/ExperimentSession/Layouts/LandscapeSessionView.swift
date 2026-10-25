//
//  LandscapeSessionView.swift
//  Researchers
//
//  Created by 정홍섭 on 10/25/26.
//

import ComposableArchitecture
import SwiftUI

struct LandscapeSessionView: View {
    let store: StoreOf<ExperimentSessionFeature>

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(.black)
            
            VStack(alignment: .leading, spacing: 020) {
                SessionHeaderView()
                
                HStack(alignment: .top, spacing: 20) {
                    SessionCaptureView()
                    
                    Spacer()
                    
                    SessionTimerView(store: store)
                }
            }
            .padding(.vertical, 30)
            .padding(.leading, 80)
            .padding(.trailing, 36)
            .foregroundStyle(.white)
        }
        .ignoresSafeArea()
    }
}

#Preview {
    LandscapeSessionView(store: Store(initialState: ExperimentSessionFeature.State()) {
        ExperimentSessionFeature()
    })
}
