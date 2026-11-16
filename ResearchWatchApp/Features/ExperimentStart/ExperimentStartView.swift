import ComposableArchitecture
import LabcordDesignSystem
import LabcordShared
import SwiftUI

struct ExperimentStartView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store: StoreOf<ExperimentStartFeature>
    let onExperimentStarted: () -> Void

    init(experiment: WatchExperimentSummary, onExperimentStarted: @escaping () -> Void) {
        _store = State(initialValue: Store(initialState: .init(experiment: experiment)) {
            ExperimentStartFeature()
        })
        self.onExperimentStarted = onExperimentStarted
    }

    var body: some View {
        Group {
            switch store.phase {
            case .details:
                VStack {
                    Text(store.experiment.title)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 6.5)

                    Spacer()

                    Button {
                        store.send(.startTapped)
                    } label: {
                        Text("실험 시작")
                            .font(.system(size: 16))
                            .foregroundStyle(Color("General/Fill/White"))
                            .frame(maxWidth: .infinity)
                            .frame(height: 45)
                            .background(
                                Color("General/Brand/Primary"),
                                in: RoundedRectangle(cornerRadius: 100)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 9.5)
                }
                .padding(.top, 14.5)
                .padding(.bottom, 10)

            case .requestingPermission:
                Color.clear

            case .permissionDenied:
                VStack(spacing: 8) {
                    Text("마이크 권한이 필요해요")
                        .font(.headline)
                    Text("Watch 설정에서 마이크 접근을 허용한 뒤\n다시 확인해 주세요.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                    Button("다시 확인") { store.send(.permissionRecheckTapped) }
                }

            case let .countdown(number):
                CountdownRingView(number: number)

            case .experiment:
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: store.phase) { _, phase in
            if phase == .experiment { onExperimentStarted() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { store.send(.becameInactive) }
        }
        .onDisappear { store.send(.disappeared) }
    }
}

private struct CountdownRingView: View {
    let number: Int?

    @State private var startedAt = Date.now

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.periodic(from: .now, by: 0.05)) { context in
                ProgressRing(
                    value: number == nil
                        ? 0
                        : (context.date.timeIntervalSince(startedAt) - 1) / 3,
                    showPercentage: false,
                    centerText: number.map(String.init) ?? "준비",
                    diameter: max(0, geometry.size.width - 14)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: -10)
            }
        }
    }
}

#Preview {
    NavigationStack {
        ExperimentStartView(
            experiment: WatchExperimentSummary(
                id: UUID(),
                title: "새 실험(1)",
                status: .ready
            )
        ) { }
    }
}
