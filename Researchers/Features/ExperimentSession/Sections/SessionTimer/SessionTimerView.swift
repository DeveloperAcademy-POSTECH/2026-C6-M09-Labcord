//
//  SessionTimerView.swift
//  Researchers
//
//  Created by 정홍섭 on 10/25/26.
//

import ComposableArchitecture
import LabcordShared
import SwiftUI

struct SessionTimerView: View {
    private struct TimerTileItem: Identifiable {
        let id: Int
        let seconds: Int
    }

    let store: StoreOf<SessionTimerFeature>
    @State private var selectedPage: Int? = 0
    @State private var selectedActivePage: Int? = 0
    @State private var isTimerSetupPresented = false
    @State private var selectedHours = 0
    @State private var selectedMinutes = 10
    @State private var selectedSeconds = 0

    var body: some View {
        let selectedTab = store.selectedTimerTab
        let timerCollection = store.timerCollection
        let currentTime = timerCollection.currentTime
        let activeTimers = timerCollection.sortedTimers
        let timerSeconds = store.timerSeconds
        let timerItems = timerSeconds.enumerated().map {
            TimerTileItem(id: $0.offset, seconds: $0.element)
        }
        let canStartTimer = timerCollection.canStartTimer
        let isFreeMode = store.mode == .free

        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                if isFreeMode {
                    Text("타이머")
                        .font(.body.weight(.semibold))
                } else {
                    HStack(spacing: 20) {
                        Button {
                            store.send(.timerTabSelected(.configured))
                        } label: {
                            Text("세팅된 타이머")
                                .foregroundStyle(
                                    selectedTab == .active
                                    ? Color.gray
                                    : Color.white
                                )
                                .font(.body.weight(.semibold))
                        }
                        .buttonStyle(.plain)

                        Button {
                            store.send(.timerTabSelected(.active))
                        } label: {
                            HStack(spacing: 8) {
                                Text("진행중인 타이머")
                                    .foregroundStyle(
                                        selectedTab == .active
                                        ? Color.white
                                        : Color.gray
                                    )
                                    .font(.body.weight(.semibold))

                                if !activeTimers.isEmpty {
                                    Text("\(activeTimers.count)")
                                        .foregroundStyle(.orange)
                                        .font(.body.weight(.semibold))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()

                Button {
                    isTimerSetupPresented = true
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(.blue)
                }
                .popover(isPresented: $isTimerSetupPresented) {
                    timerSetup(canStartTimer: canStartTimer)
                    .presentationCompactAdaptation(.popover)
                }
            }

            if isFreeMode || selectedTab == .active {
                if activeTimers.isEmpty {
                    emptyState("진행 중인 타이머가 없어요")
                } else {
                    activeTimerPages(activeTimers, at: currentTime)
                }
            } else if timerSeconds.isEmpty {
                emptyState("설정된 타이머가 없어요")
            } else {
                let tileWidth: CGFloat = 91
                let tileHeight: CGFloat = 58.67
                let tileSpacing: CGFloat = 12
                let gridHeight = tileHeight * 3 + tileSpacing * 2

                GeometryReader { geometry in
                    let threeColumnWidth = tileWidth * 3 + tileSpacing * 2
                    let columnCount = geometry.size.width >= threeColumnWidth ? 3 : 2
                    let itemsPerPage = columnCount * 3
                    let pageCount = (timerItems.count + itemsPerPage - 1) / itemsPerPage
                    let currentPage = min(selectedPage ?? 0, pageCount - 1)

                    VStack(spacing: 8) {
                        ScrollView(.horizontal) {
                            HStack(spacing: 0) {
                                ForEach(0..<pageCount, id: \.self) { page in
                                    let start = page * itemsPerPage
                                    let pageItems = Array(
                                        timerItems.dropFirst(start).prefix(itemsPerPage)
                                    )

                                    LazyVGrid(
                                        columns: Array(
                                            repeating: GridItem(
                                                .fixed(tileWidth),
                                                spacing: tileSpacing
                                            ),
                                            count: columnCount
                                        ),
                                        alignment: .leading,
                                        spacing: tileSpacing
                                    ) {
                                        ForEach(pageItems) { item in
                                            Button {
                                                store.send(.timerStarted(item.id))
                                            } label: {
                                                timerTile(item.seconds)
                                            }
                                            .buttonStyle(.plain)
                                            .disabled(!canStartTimer)
                                        }
                                    }
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

                        HStack(spacing: 6) {
                            ForEach(0..<pageCount, id: \.self) { page in
                                Circle()
                                    .fill(currentPage == page ? Color.white : Color.gray)
                                    .frame(width: 6, height: 6)
                            }
                        }
                    }
                    .onChange(of: pageCount) { _, newCount in
                        if let selectedPage, selectedPage >= newCount {
                            self.selectedPage = max(newCount - 1, 0)
                        }
                    }
                }
                .frame(height: gridHeight + 10)
            }
        }
    }

    private func timerSetup(canStartTimer: Bool) -> some View {
        let durationSeconds = selectedHours * 3600 + selectedMinutes * 60 + selectedSeconds

        return VStack(spacing: 16) {
            HStack(spacing: 0) {
                Picker("시간", selection: $selectedHours) {
                    ForEach(0...23, id: \.self) { hour in
                        Text("\(hour) 시간").tag(hour)
                    }
                }

                Picker("분", selection: $selectedMinutes) {
                    ForEach(0...59, id: \.self) { minute in
                        Text("\(minute) 분").tag(minute)
                    }
                }

                Picker("초", selection: $selectedSeconds) {
                    ForEach(0...59, id: \.self) { second in
                        Text("\(second) 초").tag(second)
                    }
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .frame(height: 150)

            Button("실행하기") {
                store.send(.customTimerStarted(durationSeconds))
                isTimerSetupPresented = false
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            .disabled(durationSeconds == 0 || !canStartTimer)
        }
        .padding()
        .frame(width: 320)
    }

    private func timerTile(_ seconds: Int) -> some View {
        Text(TimerDurationFormatter.string(from: seconds))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: 91, height: 58.67)
            .background(.gray.opacity(0.3))
            .cornerRadius(6)
    }

    private func emptyState(_ message: String) -> some View {
        Rectangle()
            .foregroundStyle(.gray.opacity(0.2))
            .frame(height: 91)
            .cornerRadius(6)
            .overlay {
                Text(message)
                    .foregroundStyle(.gray)
                    .font(.footnote)
            }
    }
}

private extension SessionTimerView {
    func activeTimerPages(_ timers: [ExperimentTimer], at date: Date) -> some View {
        let pageCount = (timers.count + 2) / 3

        return GeometryReader { geometry in
            VStack(spacing: 8) {
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
                    .frame(width: geometry.size.width, height: 186)
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
        .frame(height: 200)
    }

    func activeTimerList(
        _ timers: [ExperimentTimer],
        at date: Date,
        width: CGFloat
    ) -> some View {
        List(timers) { timer in
            activeTimerRow(timer, at: date)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .scrollDisabled(true)
        .frame(width: width, height: 186, alignment: .leading)
    }

    func activeTimerRow(_ timer: ExperimentTimer, at date: Date) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(.gray.opacity(0.3))
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .overlay {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(TimerDurationFormatter.string(from: timer.remainingSeconds(at: date)))
                            .font(.body.monospacedDigit())

                        Text(
                            "설정 \(TimerDurationFormatter.string(from: timer.durationSeconds))"
                        )
                            .font(.footnote)
                            .foregroundStyle(.gray)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                    Spacer(minLength: 8)

                    switch timer.status {
                    case .running:
                        Button("일시정지") {
                            store.send(.timerPaused(timer.id))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)

                    case .paused:
                        Button("재개") {
                            store.send(.timerResumed(timer.id))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)

                        Button("삭제") {
                            store.send(.timerDeleted(timer.id))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)

                    case .finished:
                        Button("삭제") {
                            store.send(.timerDeleted(timer.id))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, 12)
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
