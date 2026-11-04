//
//  OnboardingFooter.swift
//  Researchers
//
//  Created by lwc0113 on 11/4/26.
//

import ComposableArchitecture
import LabcordDesignSystem
import SwiftUI

struct OnboardingFooter: View {
    let store: StoreOf<OnboardingFeature>
    
    var body: some View {
        VStack(spacing: LayoutTokens.spacing16) {
            HStack(spacing: LayoutTokens.spacing8) {
                if store.page != .first {
                    Button("이전") { store.send(.previousTapped) }
                        .buttonStyle(IOSButtonStyle(.plain, size: .large))
                        .frame(width: 100)
                }
                Button {
                    store.send(store.page == .third ? .startTapped : .nextTapped)
                } label: {
                    Text(store.page == .third ? "시작" : "다음")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(IOSButtonStyle(.filled, size: .large))
            }
        }
        .padding(.horizontal, LayoutTokens.spacing16)
        .padding(.top, LayoutTokens.spacing16)
        .frame(maxWidth: .infinity)
        .background {
            if store.page != .second {
                Color("General/Background/Primary")
                    .ignoresSafeArea(edges: .bottom)
            }
        }
    }
}
