import ComposableArchitecture
import SwiftUI

struct HomeView: View {
    let store: StoreOf<HomeFeature>

    var body: some View {
        ExperimentList(store: store.scope(state: \.list, action: \.list))
            .navigationTitle("실험")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("설정", systemImage: "gearshape") {
                        store.send(.settingsTapped)
                    }
                    .accessibilityIdentifier("entry-settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("새 실험 추가", systemImage: "plus") {
                        store.send(.addTapped)
                    }
                    .accessibilityIdentifier("entry-add")
                }
            }
    }
}

#Preview {
    NavigationStack {
        HomeView(store: Store(initialState: HomeFeature.State()) {
            HomeFeature()
        })
    }
}
