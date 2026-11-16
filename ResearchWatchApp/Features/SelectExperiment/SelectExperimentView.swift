import ComposableArchitecture
import LabcordDesignSystem
import LabcordShared
import SwiftUI

struct SelectExperimentView: View {
    @State private var store = Store(initialState: SelectExperimentFeature.State()) {
        SelectExperimentFeature()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("내 실험")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Color("General/Brand/Primary"))
                .padding(.horizontal, 9.5)

            if store.isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
            } else if let errorMessage = store.errorMessage, store.experiments.isEmpty {
                Text(errorMessage)
                    .foregroundStyle(Color("Experiment/Label/Light"))
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .multilineTextAlignment(.center)
                    .font(.headline)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 26)
            } else if store.experiments.isEmpty {
                Text("진행 중인\n실험이 없어요")
                    .foregroundStyle(Color("Experiment/Label/Light"))
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .multilineTextAlignment(.center)
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 26)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(store.experiments) { experiment in
                            NavigationLink {
                                ExperimentStartView(experiment: experiment)
                            } label: {
                                ExperimentRow(title: experiment.title)
                            }
                            .buttonStyle(.plain)
                            .simultaneousGesture(TapGesture().onEnded {
                                store.send(.experimentTapped(experiment.id))
                            })
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(.top, -25)
        .task { store.send(.appeared) }
        .onDisappear { store.send(.disappeared) }
    }
}

#Preview {
    SelectExperimentView()
}
