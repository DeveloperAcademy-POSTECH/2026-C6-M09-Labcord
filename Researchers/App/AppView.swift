import ComposableArchitecture
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
            case .session(let store):
                ExperimentSessionView(store: store)
            case .result(let store):
                ExperimentResultView(store: store)
            }
        }
    }
}
