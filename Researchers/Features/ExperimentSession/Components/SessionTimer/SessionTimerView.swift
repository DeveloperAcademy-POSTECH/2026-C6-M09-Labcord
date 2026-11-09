//
//  SessionTimerView.swift
//  Researchers
//
//  Created by 정홍섭 on 10/25/26.
//

import ComposableArchitecture
import LabcordDesignSystem
import LabcordShared
import SwiftUI

struct SessionTimerView: View {
    private struct TimerTileItem: Identifiable {
        let id: Int
        let seconds: Int
    }

    let store: StoreOf<SessionTimerFeature>
    let isPortrait: Bool
    @State private var selectedPage: Int? = 0
    @State private var selectedActivePage: Int? = 0

    init(store: StoreOf<SessionTimerFeature>, isPortrait: Bool = false) {
        self.store = store
        self.isPortrait = isPortrait
    }

    var body: some View {
        let timerCollection = store.timerCollection
        let currentTime = timerCollection.currentTime
        let activeTimers = timerCollection.sortedTimers
        let timerSeconds = store.timerSeconds
        let timerItems = timerSeconds.enumerated().map {
            TimerTileItem(id: $0.offset, seconds: $0.element)
        }
        let canStartTimer = timerCollection.canStartTimer && store.canModifyTimers

        return VStack(alignment: .leading, spacing: 12) {
            if store.isEditorPresented {
                timerSetup(canStartTimer: canStartTimer)
            } else {
                timerList(
                    activeTimers: activeTimers,
                    timerItems: timerItems,
                    currentTime: currentTime,
                    canStartTimer: canStartTimer
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func timerList(
        activeTimers: [ExperimentTimer],
        timerItems: [TimerTileItem],
        currentTime: Date,
        canStartTimer: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if store.mode == .free {
                    Text("타이머")
                        .font(.body.weight(.semibold))
                } else {
                    TimerTabs(
                        selection: timerTabSelection,
                        count: activeTimers.isEmpty ? nil : activeTimers.count,
                        style: .plain,
                        leftTitle: "설정된 타이머",
                        rightTitle: "진행 중인 타이머"
                    )
                }

                Spacer()

                Button {
                    store.send(.editorPresented(true))
                } label: {
                    Image(labcordIcon: .plus)
                        .foregroundStyle(Color("Experiment/Label/Secondary"))
                }
                .buttonStyle(.labcordIcon(.plain, size: .large))
            }

            if store.mode == .free || store.selectedTimerTab == .active {
                if activeTimers.isEmpty {
                    emptyState
                } else {
                    activeTimerPages(activeTimers, at: currentTime)
                }
            } else if timerItems.isEmpty {
                emptyState
            } else {
                configuredTimerPages(timerItems, canStartTimer: canStartTimer)
            }
        }
    }

    private func configuredTimerPages(
        _ timerItems: [TimerTileItem],
        canStartTimer: Bool
    ) -> some View {
        let tileWidth: CGFloat = isPortrait ? 115 : 91
        let tileHeight: CGFloat = 60
        let tileSpacing: CGFloat = 12
        let gridHeight = tileHeight * 3 + tileSpacing * 2

        return GeometryReader { geometry in
            let threeColumnWidth = tileWidth * 3 + tileSpacing * 2
            let columnCount = geometry.size.width >= threeColumnWidth ? 3 : 2
            let itemsPerPage = columnCount * 3
            let pageCount = (timerItems.count + itemsPerPage - 1) / itemsPerPage
            let currentPage = min(selectedPage ?? 0, pageCount - 1)

            VStack(spacing: 12) {
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(0..<pageCount, id: \.self) { page in
                            let start = page * itemsPerPage
                            let pageItems = Array(
                                timerItems.dropFirst(start).prefix(itemsPerPage)
                            )

                            configuredTimerGrid(
                                pageItems,
                                columnCount: columnCount,
                                tileWidth: tileWidth,
                                tileSpacing: tileSpacing,
                                canStartTimer: canStartTimer
                            )
                            .frame(
                                width: geometry.size.width,
                                height: gridHeight,
                                alignment: .topLeading
                            )
                            .id(page)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $selectedPage)
                .clipped()
                .frame(height: gridHeight)

                configuredPageIndicators(pageCount: pageCount, currentPage: currentPage)
            }
            .onChange(of: pageCount) { _, newCount in
                if let selectedPage, selectedPage >= newCount {
                    self.selectedPage = max(newCount - 1, 0)
                }
            }
        }
        .frame(height: gridHeight + 18)
    }

    private func configuredTimerGrid(
        _ items: [TimerTileItem],
        columnCount: Int,
        tileWidth: CGFloat,
        tileSpacing: CGFloat,
        canStartTimer: Bool
    ) -> some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.fixed(tileWidth), spacing: tileSpacing),
                count: columnCount
            ),
            alignment: .leading,
            spacing: tileSpacing
        ) {
            ForEach(items) { item in
                Button {
                    store.send(.timerStarted(item.id))
                } label: {
                    let parts = TimerDurationFormatStyle()
                        .formattedParts(for: .seconds(item.seconds))
                    ProtocolTimerItem(
                        value: parts.value,
                        unit: parts.unit,
                        format: .long,
                        width: isPortrait ? tileWidth : nil
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canStartTimer)
            }
        }
    }

    private func configuredPageIndicators(pageCount: Int, currentPage: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<pageCount, id: \.self) { page in
                Circle()
                    .fill(currentPage == page ? Color.white : Color.gray)
                    .frame(width: 6, height: 6)
            }
        }
    }

    private var timerTabSelection: Binding<TimerTabs.Selection> {
        Binding(
            get: { store.selectedTimerTab == .configured ? .set : .running },
            set: { store.send(.timerTabSelected($0 == .set ? .configured : .active)) }
        )
    }

    private func timerSetup(canStartTimer: Bool) -> some View {
        let durationSeconds = store.draftSeconds

        return VStack(alignment: .leading, spacing: 12) {
            timerSetupHeader

            TimerPicker(
                hours: timerDraftBinding(unit: 3600),
                minutes: timerDraftBinding(unit: 60),
                seconds: timerDraftBinding(unit: 1),
                usage: .running
            )

            Button {
                store.send(.customTimerStarted(durationSeconds))
            } label: {
                Text("타이머 실행")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.labcord(.primary, size: .large))
            .disabled(durationSeconds == 0 || !canStartTimer)
        }
    }

    private var timerSetupHeader: some View {
        HStack(spacing: 8) {
            Button {
                store.send(.editorPresented(false))
            } label: {
                Image(labcordIcon: .caretLeft)
                    .foregroundStyle(Color("Experiment/Label/Secondary"))
            }
            .buttonStyle(.labcordIcon(.plain, size: .large))

            Text("타이머")
                .typography(Typography.bodySemiBold)
                .foregroundStyle(Color("Experiment/Label/Primary"))
        }
        .frame(height: 46)
    }

    private var emptyState: some View {
        Text("설정된 타이머가 없어요.")
            .typography(Typography.callout)
            .foregroundStyle(Color("Experiment/Label/Tertiary"))
            .frame(maxWidth: .infinity)
            .padding(.top, LayoutTokens.spacing24)
    }
}

private extension SessionTimerView {
    func timerDraftBinding(unit: Int) -> Binding<Int> {
        Binding(
            get: { unit == 3600 ? store.draftSeconds / unit : store.draftSeconds / unit % 60 },
            set: { value in
                let previous = unit == 3600
                    ? store.draftSeconds / unit : store.draftSeconds / unit % 60
                store.send(.draftSecondsChanged(store.draftSeconds + (value - previous) * unit))
            }
        )
    }

    func activeTimerPages(_ timers: [ExperimentTimer], at date: Date) -> some View {
        let pageCount = (timers.count + 2) / 3

        return GeometryReader { geometry in
            VStack(spacing: 12) {
                if pageCount == 1 {
                    activeTimerList(timers, at: date, width: geometry.size.width)
                } else {
                    ScrollView(.horizontal) {
                        HStack(spacing: 0) {
                            ForEach(0..<pageCount, id: \.self) { page in
                                let pageTimers = Array(timers.dropFirst(page * 3).prefix(3))

                                activeTimerList(pageTimers, at: date, width: geometry.size.width)
                                    .id(page)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollIndicators(.hidden)
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: $selectedActivePage)
                    .frame(width: geometry.size.width, height: 210)
                    .clipped()
                }

                HStack(spacing: 6) {
                    ForEach(0..<pageCount, id: \.self) { page in
                        Circle()
                            .fill(
                                min(selectedActivePage ?? 0, pageCount - 1) == page
                                    ? Color.white : Color.gray
                            )
                            .frame(width: 6, height: 6)
                    }
                }
            }
            .onChange(of: pageCount) { _, newCount in
                if let selectedActivePage, selectedActivePage >= newCount {
                    self.selectedActivePage = max(newCount - 1, 0)
                }
            }
        }
        .frame(height: 228)
    }

    func activeTimerList(
        _ timers: [ExperimentTimer],
        at date: Date,
        width: CGFloat
    ) -> some View {
        VStack(spacing: 0) {
            ForEach(timers) { timer in
                TimerItem(
                    timer.id,
                    remainingTime: .seconds(timer.remainingSeconds(at: date)),
                    setDuration: .seconds(timer.durationSeconds),
                    format: timer.durationSeconds >= 3600
                        ? .hourMinuteSecond : .minuteSecond,
                    state: timerItemState(for: timer.status),
                    onToggle: {
                        switch timer.status {
                        case .running:
                            store.send(.timerPaused(timer.id))
                        case .paused:
                            store.send(.timerResumed(timer.id))
                        case .finished:
                            break
                        }
                    },
                    onRemove: { store.send(.timerDeleted(timer.id)) }
                )
                .disabled(!store.canModifyTimers)
            }
        }
        .frame(width: width, height: 210, alignment: .top)
    }

    func timerItemState(for status: ExperimentTimer.Status) -> TimerItem<UUID>.State {
        switch status {
        case .running: .running
        case .paused: .paused
        case .finished: .completed
        }
    }
}

#Preview {
    SessionTimerView(
        store: Store(initialState: SessionTimerFeature.State()) {
            SessionTimerFeature()
        }
    )
}
