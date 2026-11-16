import LabcordDesignSystem
import LabcordShared
import LabcordWatchOS
import SwiftUI

struct ExperimentView: View {
    let experiment: WatchExperimentSummary
    @State private var selectedPage = 1

    var body: some View {
        VStack {
            Text("실험 중")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color("General/Brand/Primary"))
                .padding(.bottom, WatchScreenMetrics.scaledHeight(4.5))

            TabView(selection: $selectedPage) {
                ExperimentRecordView(title: experiment.title)
                    .tag(1)

                ExperimentTimerView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
