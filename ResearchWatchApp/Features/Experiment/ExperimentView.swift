import ComposableArchitecture
import LabcordDesignSystem
import LabcordShared
import LabcordWatchOS
import SwiftUI

struct ExperimentView: View {
    let experiment: WatchExperimentSummary
    @State private var store: StoreOf<ExperimentFeature>
    @State private var selectedPage = 1

    private var showsTimerAddButton: Bool {
        guard selectedPage == 2 else { return false }
        return store.snapshot?.mode != .procedure ||
            store.snapshot?.timers.contains { $0.status == .running } == true
    }

    init(experiment: WatchExperimentSummary) {
        self.experiment = experiment
        _store = State(initialValue: Store(
            initialState: ExperimentFeature.State(experimentID: experiment.id)
        ) {
            ExperimentFeature()
        })
    }

    var body: some View {
        VStack {
            Text(selectedPage == 1 ? "실험 중" : "타이머")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color("General/Brand/Primary"))
                .padding(.bottom, WatchScreenMetrics.scaledHeight(4.5))

            TabView(selection: $selectedPage) {
                ExperimentRecordView(title: experiment.title)
                    .tag(1)

                ExperimentTimerView(
                    mode: store.snapshot?.mode,
                    timers: store.snapshot?.timers ?? [],
                    protocolTimerSeconds: store.snapshot?.protocolTimerSeconds ?? []
                )
                    .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .overlay(alignment: .bottom) {
                PageControl(pageCount: 2, selection: $selectedPage)
            }
        }
        .padding(.top, 24.5)
        .padding(.horizontal, 6)
        .ignoresSafeArea()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if showsTimerAddButton {
                    Button {} label: {
                        Image(systemName: "plus")
                    }
                } else {
                    Color.clear
                        .frame(width: 1, height: 1)
                }
            }
        }
        .onAppear { store.send(.appeared) }
        .onDisappear { store.send(.disappeared) }
    }
}

#Preview {
    ExperimentView(
        experiment: WatchExperimentSummary(
            id: UUID(),
            title: "새 실험(1)",
            status: .running
        )
    )
}
