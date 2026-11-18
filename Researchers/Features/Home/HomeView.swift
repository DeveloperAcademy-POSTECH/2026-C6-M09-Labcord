import ComposableArchitecture
import SwiftUI

struct HomeView: View {
    let store: StoreOf<HomeFeature>

    private var showsDemoExperiment: Bool {
        #if DEBUG
        store.list.includesDemo
        #else
        false
        #endif
    }

    var body: some View {
        if store.isFirstHome && !showsDemoExperiment {
            FirstHomeView(store: store)
        } else {
            DefaultHomeView(store: store)
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
