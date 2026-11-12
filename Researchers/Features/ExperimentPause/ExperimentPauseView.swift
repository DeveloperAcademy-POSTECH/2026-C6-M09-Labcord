//
//  ExperimentPauseView.swift
//  Researchers
//
//  Created by 정홍섭 on 11/5/26.
//

import ComposableArchitecture
import LabcordDesignSystem
import LabcordiOS
import LabcordShared
import SwiftUI

struct ExperimentPauseView: View {
    let store: StoreOf<ExperimentPauseFeature>
    let timerStore: StoreOf<SessionTimerFeature>
    let canCloseSession: Bool

    private var displayedTimerCollection: ExperimentTimerCollection {
        guard timerStore.isSaving, let pendingSave = timerStore.pendingSave else {
            return timerStore.timerCollection
        }
        return pendingSave.collection
    }

    var body: some View {
        let timerCollection = displayedTimerCollection
        let visibleTimers = timerCollection.sortedTimers.filter { $0.status != .finished }

        return GeometryReader { geometry in
            ZStack {
                Color("Experiment/Overlay/Scrim")
                    .background(
                        VisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
                    )
                    .ignoresSafeArea()

                if geometry.size.width > geometry.size.height {
                    landscapeContent(
                        timers: visibleTimers,
                        collection: timerCollection,
                        availableWidth: geometry.size.width - 32
                    )
                } else {
                    portraitContent(timers: visibleTimers, collection: timerCollection)
                }
            }
        }
        .alert(
            "실험 일시정지 저장 실패",
            isPresented: Binding(
                get: { store.exitFailed },
                set: { if !$0 { store.send(.dismissHomeExitFailure) } }
            )
        ) {
            Button("다시 시도") {
                store.send(.returnHomeTapped)
            }
            Button("닫기", role: .cancel) {
                store.send(.dismissHomeExitFailure)
            }
        } message: {
            Text("실험 상태를 저장하지 못했습니다.")
        }
    }

    private func portraitContent(
        timers: [ExperimentTimer],
        collection: ExperimentTimerCollection
    ) -> some View {
        VStack {
            navigationControls
                .padding(.top, 16)

            Spacer()

            VStack(spacing: 16) {
                timerDescription

                VStack(alignment: .trailing, spacing: 12) {
                    stopAllButton(collection: collection)

                    if timers.isEmpty {
                        emptyTimerState
                            .frame(height: 353)
                    } else {
                        timerRows(timers, collection: collection)
                            .frame(height: 353, alignment: .top)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func landscapeContent(
        timers: [ExperimentTimer],
        collection: ExperimentTimerCollection,
        availableWidth: CGFloat
    ) -> some View {
        VStack(spacing: 20) {
            navigationControls

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .bottom) {
                    timerDescription
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer()

                    stopAllButton(collection: collection)
                }
                .frame(width: min(650, availableWidth))
                .layoutPriority(1)

                if timers.isEmpty {
                    emptyTimerState
                        .frame(width: min(650, availableWidth), height: 211)
                } else {
                    HStack(alignment: .top, spacing: 20) {
                        timerRows(Array(timers.prefix(3)), collection: collection)
                            .frame(width: 315, alignment: .topLeading)

                        if timers.count > 3 {
                            timerRows(Array(timers.dropFirst(3)), collection: collection)
                                .frame(width: 315, alignment: .topLeading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 22)
    }

    private var navigationControls: some View {
        HStack(spacing: 8) {
            Button {
                store.send(.resumeTapped)
            } label: {
                Image(labcordIcon: .play)
                    .foregroundStyle(Color("Experiment/Label/Primary"))
            }
            .buttonStyle(.labcordIcon(.neutral, size: .large))

            Button {
                store.send(.returnHomeTapped)
            } label: {
                Text("홈으로 이동")
                    .foregroundStyle(Color("Experiment/Label/Primary"))
            }
            .buttonStyle(.labcord(.plain, size: .medium))
            .disabled(!canCloseSession)

            Spacer()

            SlideToEndButton(
                isTriggered: Binding(
                    get: { store.isEndTriggered },
                    set: { store.send(.endTriggerChanged($0)) }
                )
            ) {
                store.send(.stopTapped)
            }
            .disabled(!canCloseSession)
        }
    }

    private var timerDescription: some View {
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

    private func stopAllButton(collection: ExperimentTimerCollection) -> some View {
        Button {
            timerStore.send(.allTimersPaused)
        } label: {
            Text("모두 정지")
                .foregroundStyle(Color("Experiment/Label/Primary"))
        }
        .buttonStyle(.labcord(.plain, size: .medium))
        .disabled(!collection.hasRunningTimers || !timerStore.canModifyTimers)
    }

    private var emptyTimerState: some View {
        Color.clear
            .overlay {
                Text("진행 중인 타이머가 없습니다.")
                    .typography(Typography.callout)
                    .foregroundStyle(Color("Experiment/Label/Primary"))
            }
    }

    private func timerRows(
        _ timers: [ExperimentTimer],
        collection: ExperimentTimerCollection
    ) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(timers) { timer in
                TimerItem(
                    timer.id,
                    remainingTime: .seconds(
                        timer.remainingSeconds(at: collection.currentTime)
                    ),
                    setDuration: .seconds(timer.durationSeconds),
                    format: timer.durationSeconds >= 3600
                    ? .hourMinuteSecond : .minuteSecond,
                    state: timer.status == .running ? .running : .paused,
                    onToggle: {
                        if timer.status == .running {
                            timerStore.send(.timerPaused(timer.id))
                        } else {
                            timerStore.send(.timerResumed(timer.id))
                        }
                    },
                    onRemove: { timerStore.send(.timerDeleted(timer.id)) }
                )
                .disabled(!timerStore.canModifyTimers)
            }
        }
    }
}

#Preview {
    ExperimentPauseView(
        store: Store(
            initialState: ExperimentPauseFeature.State(experimentID: UUID())
        ) {
            ExperimentPauseFeature()
        },
        timerStore: Store(initialState: SessionTimerFeature.State()) {
            SessionTimerFeature()
        },
        canCloseSession: true
    )
}
