import ComposableArchitecture
import LabcordDesignSystem
import SwiftUI

struct FirstHomeView: View {
    let store: StoreOf<HomeFeature>

    var body: some View {
        ZStack {
            Color("General/Background/Primary")
                .ignoresSafeArea()

            FirstHomeEmptyContent {
                store.send(.firstHomeRegisterTapped)
            }
            .disabled(store.requiresGesturePractice)
            .accessibilityHidden(store.requiresGesturePractice)

            if store.isGuideVisible {
                if store.requiresGesturePractice {
                    Color.black.opacity(0.4).ignoresSafeArea()
                } else {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture { store.send(.firstHomeGuideDismissed) }
                }
            }

        }
        .overlay(alignment: .bottomTrailing) {
            VStack(alignment: .trailing, spacing: 0) {
                if store.isGuideVisible {
                    FirstHomeGuideTooltip()
                }

                FirstHomeHelpButton {
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
