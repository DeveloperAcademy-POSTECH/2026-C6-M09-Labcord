import ComposableArchitecture
import LabcordiOS
import SwiftUI

struct AppView: View {
    @State private var store = Store(initialState: AppFeature.State()) {
        AppFeature()
    }

    var body: some View {
        @Bindable var store = store

        Group {
            if let onboardingStore = store.scope(state: \.onboarding, action: \.onboarding) {
                OnboardingView(store: onboardingStore)
            } else if let firstHomeStore = store.scope(state: \.firstHome, action: \.firstHome) {
                FirstHomeView(store: firstHomeStore)
            } else {
                NavigationStack(path: $store.scope(\.path, action: \.path)) {
                    HomeView(store: store.scope(state: \.home, action: \.home))
                } destination: { store in
                    switch store.case {
                    case .registration(let store):
                        ProtocolRegistrationView(store: store)
                            .navigationSwipeBackEnabled(!store.isSaving)

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
        .task {
            store.send(.appeared)
        }
    }
}
