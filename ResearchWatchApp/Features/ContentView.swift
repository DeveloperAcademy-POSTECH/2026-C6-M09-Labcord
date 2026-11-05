import ComposableArchitecture
import SwiftUI

struct ContentView: View {
    let store: StoreOf<WatchExperimentFeature>
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            WatchExperimentView(store: store)
        }
        .task { store.send(.appeared) }
        .onChange(of: scenePhase) { _, phase in
            store.send(phase == .active ? .appeared : .inactive)
        }
        .onDisappear { store.send(.inactive) }
    }
}
