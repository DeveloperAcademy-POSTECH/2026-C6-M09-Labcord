//
//  OnboardingView.swift
//  Researchers
//
//  Created by lwc0113 on 11/2/26.
//

import ComposableArchitecture
import LabcordDesignSystem
import SwiftUI

struct OnboardingView: View {
    let store: StoreOf<OnboardingFeature>

    var body: some View {
        ZStack {
            OnboardingBackground(showsLabImage: store.page == .second)

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    OnboardingSkipRow(store: store)
                    OnboardingHeader(store: store)
                        .padding(.top, 19)

                    if store.page != .second {
                        OnboardingCard(imageName: cardImageName)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.top, LayoutTokens.spacing24)
                            .overlay(alignment: .bottom) {
                                pageControl
                            }
                    } else {
                        Spacer(minLength: 0)
                        pageControl
                    }
                }
                .padding(.horizontal, LayoutTokens.spacing16)
                .padding(.top, 19)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                OnboardingFooter(store: store)
            }
        }
    }

    private var cardImageName: String {
        store.page == .first ? "onboarding_protocol2" : "onboarding_result2"
    }

    private var pageControl: some View {
        PageControl(
            pageCount: 3,
            selection: .constant(store.page.rawValue + 1),
            appearance: .general
        )
    }
}

#Preview {
    OnboardingView(store: Store(initialState: OnboardingFeature.State()) {
        OnboardingFeature()
    })
}
