import ComposableArchitecture
import SwiftUI

struct ExperimentEntryView: View {
    @Bindable var store: StoreOf<ExperimentEntryFeature>

    var body: some View {
        HomeView(store: store.scope(state: \.home, action: \.home))
            .navigationDestination(
                isPresented: $store.isRegistering.sending(\.registrationPresented)
            ) {
                ProtocolRegistrationView(
                    store: store.scope(state: \.registration, action: \.registration)
                )
            }
    }
}
