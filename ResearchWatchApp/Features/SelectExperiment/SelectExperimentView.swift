import ComposableArchitecture
import LabcordDesignSystem
import LabcordShared
import SwiftUI

struct SelectExperimentView: View {
    @State private var store = Store(initialState: SelectExperimentFeature.State()) {
        SelectExperimentFeature()
    }
    let onSelect: (WatchExperimentSummary) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("내 실험")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Color("General/Brand/Primary"))
                .padding(.horizontal, 9.5)

            if store.isLoading, store.list == nil {
                VStack(spacing: 4) {
                    Text("실험 불러오는 중")

                    ProgressView()
                        .progressViewStyle(.circular)
                        .fixedSize()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.experiments.isEmpty,
                      store.list == nil || store.errorMessage != nil {
                VStack(spacing: 12) {
                    Text(store.errorMessage ?? "실험 목록을 다시 불러와 주세요.")
                        .foregroundStyle(Color("Experiment/Label/Light"))
                        .multilineTextAlignment(.center)
                        .font(.headline)
                    Button("다시 시도") { store.send(.retryTapped) }
                }
                .padding(.horizontal, 10)
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
                        if let message = store.errorMessage {
                            Text(message)
                                .font(.caption2)
                                .multilineTextAlignment(.center)
                            Button("다시 시도") { store.send(.retryTapped) }
                        }
                        ForEach(store.experiments) { experiment in
                            Button {
                                onSelect(experiment)
                            } label: {
                                ExperimentRow(title: experiment.title)
                            }
                            .buttonStyle(.plain)
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
    SelectExperimentView { _ in }
}
