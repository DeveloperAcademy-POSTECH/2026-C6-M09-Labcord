import ComposableArchitecture
import LabcordiOS
import SwiftUI

struct AppView: View {
    @State private var store = Store(initialState: AppFeature.State()) {
        AppFeature()
    }

    var body: some View {
        @Bindable var store = store

        NavigationStack(path: $store.scope(\.path, action: \.path)) {
            HomeView(store: store.scope(state: \.home, action: \.home))
        } destination: { store in
            switch store.case {
            case .registration(let store):
                ProtocolRegistrationView(store: store)
                    .navigationSwipeBackEnabled(
                        !store.isSaving && !store.importing && store.analysisID == nil
                            && !store.analysisStarting && store.invalidatingJobID == nil
                    )

            case .recent(let store):
                RecentProtocolView(store: store)

            case .session(let store):
                ExperimentSessionView(store: store)
                    .navigationSwipeBackEnabled(false)

            case .result(let store):
                ExperimentResultView(store: store)
                    .navigationSwipeBackEnabled(store.isOpenedFromHome)
            }
        }
    }
}
