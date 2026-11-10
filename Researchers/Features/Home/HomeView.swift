import ComposableArchitecture
import LabcordDesignSystem
import SwiftUI

struct HomeView: View {
    let store: StoreOf<HomeFeature>

    var body: some View {
        ExperimentList(store: store.scope(state: \.list, action: \.list))
            .padding(.top, 54)
            .padding(.horizontal, 16)
            .overlay(alignment: .bottomTrailing) {
                VStack(spacing: LayoutTokens.spacing12) {
                    Button {
                        store.send(.gestureGuideTapped)
                    } label: {
                        Image(labcordIcon: .questionmark)
                    }
                    .buttonStyle(
                        .labcordIcon(.neutral, size: .large, isLoading: false)
                    )

                    Button {
                        store.send(.addTapped)
                    } label: {
                        Image(labcordIcon: .plus)
                    }
                    .buttonStyle(
                        .labcordIcon(.primary, size: .large, isLoading: false)
                    )
                }
                .padding(.trailing, 20)
                .padding(.bottom, 17)
            }
            .background(
                Color("General/Background/Primary")
                    .ignoresSafeArea()
            )
    }
}

#Preview {
    NavigationStack {
        HomeView(store: Store(initialState: HomeFeature.State()) {
            HomeFeature()
        })
    }
}
