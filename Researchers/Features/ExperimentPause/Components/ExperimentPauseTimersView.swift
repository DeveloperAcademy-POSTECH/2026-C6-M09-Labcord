import ComposableArchitecture
import LabcordDesignSystem
import LabcordShared
import SwiftUI

struct ExperimentPauseTimersView: View {
    let store: StoreOf<SessionTimerFeature>
    let collection: ExperimentTimerCollection
    let isLandscape: Bool
    let availableWidth: CGFloat

    private var timers: [ExperimentTimer] {
        collection.sortedTimers.filter { $0.status != .finished }
    }

    var body: some View {
        if isLandscape {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .bottom) {
                    description
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer()

                    stopAllButton
                }
                .frame(width: min(650, availableWidth))
                .layoutPriority(1)

                if timers.isEmpty {
                    emptyState
                        .frame(width: min(650, availableWidth), height: 211)
                } else {
                    HStack(alignment: .top, spacing: 20) {
                        timerRows(Array(timers.prefix(3)))
                            .frame(width: 315, alignment: .topLeading)

                        if timers.count > 3 {
                            timerRows(Array(timers.dropFirst(3)))
                                .frame(width: 315, alignment: .topLeading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: timers.count <= 2 ? 211 : nil, alignment: .top)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(spacing: 16) {
                description

                VStack(alignment: .trailing, spacing: 12) {
                    stopAllButton

                    if timers.isEmpty {
                        emptyState.frame(height: 353)
                    } else {
                        timerRows(timers)
                            .frame(height: 353, alignment: .top)
                    }
                }
            }
        }
    }

    private var description: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("진행 중인 타이머")
                .typography(Typography.title3)
                .foregroundStyle(Color("Experiment/Label/Primary"))

            Text(
                """
                앱을 닫아도 타이머는 계속 진행돼요.
                실험을 종료하면 진행 중인 타이머도 함께 종료돼요.
                """
            )
            .typography(Typography.callout)
            .foregroundStyle(Color("Experiment/Label/Secondary"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stopAllButton: some View {
        Button {
            store.send(.allTimersPaused)
        } label: {
            Text("모두 정지")
                .foregroundStyle(Color("Experiment/Label/Primary"))
        }
        .buttonStyle(.labcord(.plain, size: .medium))
        .disabled(!collection.hasRunningTimers || !store.canModifyTimers)
    }

    private var emptyState: some View {
        Text("진행 중인 타이머가 없습니다.")
            .typography(Typography.callout)
            .foregroundStyle(Color("Experiment/Label/Primary"))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func timerRows(_ timers: [ExperimentTimer]) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(timers) { timer in
                TimerItem(
                    timer.id,
                    remainingTime: .seconds(timer.remainingSeconds(at: collection.currentTime)),
                    setDuration: .seconds(timer.durationSeconds),
                    format: timer.durationSeconds >= 3600 ? .hourMinuteSecond : .minuteSecond,
                    state: timer.status == .running ? .running : .paused,
                    onToggle: {
                        store.send(timer.status == .running
                            ? .timerPaused(timer.id) : .timerResumed(timer.id)
                        )
                    },
                    onRemove: { store.send(.timerDeleted(timer.id)) }
                )
                .disabled(!store.canModifyTimers)
            }
        }
    }
}
