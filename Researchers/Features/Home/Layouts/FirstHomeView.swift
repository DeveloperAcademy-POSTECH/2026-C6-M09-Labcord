import ComposableArchitecture
import LabcordDesignSystem
import SwiftUI

struct FirstHomeView: View {
    let store: StoreOf<HomeFeature>

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color("General/Background/Primary")
                .ignoresSafeArea()

            FirstHomeEmptyContent {
                store.send(.firstHomeRegisterTapped)
            }
            .allowsHitTesting(!store.isGuideVisible)
            .accessibilityHidden(store.isGuideVisible)

            if store.isGuideVisible {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        if !store.requiresGesturePractice {
                            store.send(.firstHomeGuideDismissed)
                        }
                    }
            }

            VStack(alignment: .trailing, spacing: 3) {
                if store.isGuideVisible {
                    FirstHomeGuideTooltip()
                }

                FirstHomeHelpButton(isGuideVisible: store.isGuideVisible) {
                    store.send(.gestureGuideTapped)
                }
            }
            .padding(.trailing, 20)
            .padding(.bottom, 17)
        }
        .task {
            store.send(.firstHomeAppeared)
        }
    }
}

#Preview {
    FirstHomeView(store: Store(initialState: HomeFeature.State()) {
        HomeFeature()
    })
}
