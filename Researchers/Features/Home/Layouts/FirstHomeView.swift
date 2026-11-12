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
            .allowsHitTesting(!store.requiresGesturePractice)
            .accessibilityHidden(store.requiresGesturePractice)

            if store.isGuideVisible {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .allowsHitTesting(!store.requiresGesturePractice)
                    .onTapGesture {
                        store.send(.firstHomeGuideDismissed)
                    }
            }

            VStack(alignment: .trailing, spacing: 0) {
                if store.isGuideVisible {
                    FirstHomeGuideTooltip()
                        .allowsHitTesting(false)
                }

                FirstHomeHelpButton {
                    store.send(.gestureGuideTapped)
                }
            }
            .padding(.trailing, 20)
            .padding(.bottom, 17)
            .zIndex(1)
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
