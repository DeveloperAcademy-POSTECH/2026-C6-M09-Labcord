import ComposableArchitecture
import LabcordDesignSystem
import SwiftUI

struct FirstHomeView: View {
    let store: StoreOf<FirstHomeFeature>

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color("General/Background/Primary")
                .ignoresSafeArea()

            FirstHomeEmptyContent {
                store.send(.registerTapped)
            }

            if store.isGuideVisible {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        store.send(.guideDismissed)
                    }
            }

            VStack(alignment: .trailing, spacing: 0) {
                if store.isGuideVisible {
                    FirstHomeGuideTooltip()
                }

                FirstHomeHelpButton {
                    store.send(.helpTapped)
                }
            }
            .padding(.trailing, 20)
            .padding(.bottom, 17)
        }
        .task {
            store.send(.appeared)
        }
    }
}

#Preview {
    FirstHomeView(store: Store(initialState: FirstHomeFeature.State()) {
        FirstHomeFeature()
    })
}
