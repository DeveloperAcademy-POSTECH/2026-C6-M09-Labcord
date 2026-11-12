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

            if store.isGuideVisible {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        store.send(.firstHomeGuideDismissed)
                    }
            }

            VStack(alignment: .trailing, spacing: 0) {
                if store.isGuideVisible {
                    FirstHomeGuideTooltip()
                }

                FirstHomeHelpButton {}
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
