import ComposableArchitecture
import LabcordShared
import SwiftUI

struct WatchPreparationView: View {
    let value: String

    var body: some View {
        Image("WatchPreparationRing")
            .resizable()
            .scaledToFit()
            .frame(maxWidth: 149)
            .overlay {
                Text(value)
                    .font(.system(size: 36, weight: .medium, design: .rounded))
                    .monospacedDigit()
            }
            .accessibilityLabel(value == "준비" ? "실험 준비" : "실험 시작까지 \(value)초")
    }
}

extension WatchExperimentView {
    @ViewBuilder
    var recordCleanup: some View {
        if store.canReviewCompletedExperiment {
            Image(systemName: "iphone")
                .font(.system(size: 38, weight: .medium))
                .accessibilityHidden(true)
                .padding(.top, 8)
            Text("iPhone에서\n기록을 확인하세요.")
                .font(.footnote.weight(.medium))
                .multilineTextAlignment(.center)
            Button("확인") { store.send(.closeTapped) }
                .frame(maxWidth: .infinity)
        } else if store.pending?.command.operation == .complete,
                  store.pending?.phase == .processing {
            ProgressView()
                .controlSize(.large)
                .padding(.top, 16)
            Text("실험 기록을\n정리중이에요.")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("최종 저장 결과를 확인하고 있어요.")
                .font(.caption)
        } else {
            Text("기록 저장·정리 결과를 확인해주세요.")
                .font(.headline)
            ForEach(unsettledRecords) { record in
                Button("기록 결과 확인") {
                    store.send(.closeTapped)
                    store.send(.recording(.open(record.id)))
                }
            }
            Button("상태 다시 확인") { store.send(.refresh) }
                .disabled(!store.isReachable)
            Button("실험으로 돌아가기") { store.send(.closeTapped) }
        }
    }

    private var unsettledRecords: [WatchRecordPresentation] {
        store.recording.records.values
            .filter { $0.experimentID == store.selectedID && !$0.isSettled }
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }
}
