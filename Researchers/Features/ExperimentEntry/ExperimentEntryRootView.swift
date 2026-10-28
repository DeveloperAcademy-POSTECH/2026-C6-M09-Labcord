import ComposableArchitecture
import SwiftUI

struct ExperimentEntryRootView: View {
    @State private var store = Store(initialState: ExperimentEntryFeature.State()) {
        ExperimentEntryFeature()
    }

    var body: some View {
        ExperimentEntryView(store: store)
    }
}
