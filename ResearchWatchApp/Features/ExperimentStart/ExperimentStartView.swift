import ComposableArchitecture
import LabcordDesignSystem
import LabcordShared
import LabcordWatchOS
import SwiftUI

struct ExperimentStartView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var store: StoreOf<ExperimentStartFeature>
    let onStartAttempt: () -> Void
    let onExperimentStarted: () -> Void

    init(
        experiment: WatchExperimentSummary,
        onStartAttempt: @escaping () -> Void = {},
        onExperimentStarted: @escaping () -> Void
    ) {
        _store = State(initialValue: Store(initialState: .init(experiment: experiment)) {
            ExperimentStartFeature()
        })
        self.onStartAttempt = onStartAttempt
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
                        onStartAttempt()
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

            case .checkingActiveExperiment:
                VStack {
                    ProgressView("iPhone에서 실험 확인 중")
                    Button("취소") { store.send(.cancelTapped) }
                }

            case .waitingForPhone:
                VStack {
                    Text("iPhone에서 실험이 열리기를 기다리고 있어요.")
                    Button("다시 확인") { store.send(.retryTapped) }
                    Button("취소") { store.send(.cancelTapped) }
                }
                .multilineTextAlignment(.center)

            case let .failed(error):
                VStack {
                    Text(error == .experimentNotFound || error == .invalidState
                         ? "이 실험을 시작할 수 없어요." : "iPhone에서 실험을 확인하지 못했어요.")
                    Button("다시 시도") { store.send(.retryTapped) }
                    Button("취소") { store.send(.cancelTapped) }
                }
                .multilineTextAlignment(.center)

            case .requestingPermission:
                ProgressView("마이크 권한 확인 중")

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
                    .padding(.horizontal, 7)

            case .experiment:
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if store.isActiveExperimentConflictPresented {
                ActiveExperimentConflictOverlay {
                    closeActiveExperimentConflict()
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.isActiveExperimentConflictPresented)
        .navigationBarBackButtonHidden(store.isActiveExperimentConflictPresented)
        .toolbar {
            if store.isActiveExperimentConflictPresented {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        closeActiveExperimentConflict()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("닫기")
                }
            }
        }
        .onChange(of: store.phase) { _, phase in
            if phase == .experiment { onExperimentStarted() }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            if phase == .inactive, store.phase == .requestingPermission { return }
            store.send(.becameInactive)
        }
        .onDisappear { store.send(.disappeared) }
    }
}

private extension ExperimentStartView {
    func closeActiveExperimentConflict() {
        store.send(.activeExperimentConflictDismissed)
        dismiss()
    }
}

private struct ActiveExperimentConflictOverlay: View {
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: WatchScreenMetrics.scaledHeight(4)) {
                Text("다른 실험이\n진행 중이에요")
                    .font(.headline)
                    .multilineTextAlignment(.center)

                Spacer()

                Button("확인", action: onDismiss)
            }
            .padding(.horizontal, 9.5)
            .padding(.bottom, 10)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
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
