//
//  RunningTimerView.swift
//  ResearchWatch Watch App
//
//  Created by 정홍섭 on 11/17/26.
//

import LabcordDesignSystem
import LabcordShared
import LabcordWatchOS
import SwiftUI

struct RunningTimerView: View {
    let timer: WatchTimerSnapshot
    let isCommandPending: Bool
    var isCreating = false
    let onPause: () -> Void
    let onResume: () -> Void
    let onDelete: () -> Void
    @State private var swipeOffset: CGFloat = 0
    @State private var isDeleteRevealed = false
    @State private var showsCreatingIndicator = false

    private var canSwipeDelete: Bool {
        timer.status == .paused && !isCommandPending
    }

    private let deleteButtonSize: CGFloat = 34
    private var revealWidth: CGFloat {
        deleteButtonSize + 4
    }

    private var timerInterval: ClosedRange<Date> {
        let end = timer.measuredAt.addingTimeInterval(TimeInterval(max(0, timer.remainingSeconds)))
        let start = end.addingTimeInterval(-TimeInterval(max(1, timer.durationSeconds)))
        return start...end
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            if canSwipeDelete {
                deleteButton
                    .opacity(min(1, -swipeOffset / revealWidth))
            }

            card
                .offset(x: swipeOffset)
        }
        .simultaneousGesture(swipeGesture, including: canOpenBySwipe ? .all : .subviews)
        .highPriorityGesture(swipeGesture, including: isDeleteRevealed ? .all : .subviews)
        .onChange(of: canSwipeDelete) { _, canSwipe in
            if !canSwipe { setDeleteRevealed(false) }
        }
        .task(id: isCreating) {
            guard isCreating else {
                showsCreatingIndicator = false
                return
            }
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            showsCreatingIndicator = true
        }
    }

    private var canOpenBySwipe: Bool {
        canSwipeDelete && !isDeleteRevealed
    }

    private var deleteButton: some View {
        Button(action: onDelete) {
            Image(systemName: "trash")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color("General/Action/Destructive/Foreground"))
                .frame(width: deleteButtonSize, height: deleteButtonSize)
                .background(Color("General/Action/Destructive/Background"), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("타이머 삭제")
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard canSwipeDelete,
                      abs(value.translation.width) > abs(value.translation.height) else { return }
                let base = isDeleteRevealed ? -revealWidth : 0
                swipeOffset = min(0, max(-revealWidth, base + value.translation.width))
            }
            .onEnded { value in
                guard canSwipeDelete,
                      abs(value.translation.width) > abs(value.translation.height) else {
                    setDeleteRevealed(isDeleteRevealed && canSwipeDelete)
                    return
                }
                let base = isDeleteRevealed ? -revealWidth : 0
                setDeleteRevealed(base + value.predictedEndTranslation.width < -revealWidth / 2)
            }
    }

    private func setDeleteRevealed(_ revealed: Bool) {
        withAnimation(.snappy(duration: 0.2)) {
            isDeleteRevealed = revealed
            swipeOffset = revealed ? -revealWidth : 0
        }
    }

    private var card: some View {
        TimelineView(.animation(paused: timer.status != .running)) { context in
            let remaining = timer.remaining(at: context.date)
            let isFinished = timer.status == .finished || remaining == 0
            let ringProgress = timer.status == .running
                ? progress(at: context.date)
                : timer.durationSeconds > 0
                    ? min(1, Double(remaining) / Double(timer.durationSeconds)) : 0

            HStack(alignment: .center) {
                VStack(alignment: .leading) {
                    Text(TimerDurationFormatter.string(from: timer.durationSeconds))
                        .font(.footnote)
                        .foregroundStyle(Color.gray)
                    Text(
                        Duration.seconds(remaining).formatted(
                            .labcordClock(includesHours: timer.durationSeconds >= 3_600)
                        )
                    )
                    .font(.title3)
                    .monospacedDigit()
                    .foregroundStyle(Color.white)
                }
                .frame(height: WatchScreenMetrics.scaledHeight(38))

                Spacer()

                Button {
                    guard !showsCreatingIndicator else { return }
                    if isFinished {
                        onDelete()
                    } else if timer.status == .running {
                        onPause()
                    } else {
                        onResume()
                    }
                } label: {
                    Group {
                        if showsCreatingIndicator {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        } else {
                            Image(systemName: isFinished ? "xmark" :
                                  timer.status == .running ? "pause.fill" : "play.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 30, height: 30)
                    .background(
                        isFinished
                            ? Color("General/Timer/Identity/04")
                            : Color("General/Label/Primary"),
                        in: Circle()
                    )
                    .overlay {
                        TimerRingView(progress: ringProgress, isFinished: isFinished)
                    }
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(isCommandPending && !showsCreatingIndicator)
                .accessibilityLabel(accessibilityLabel(isFinished: isFinished))
            }
            .padding(.horizontal, WatchScreenMetrics.scaledWidth(9.5))
            .padding(.vertical, WatchScreenMetrics.scaledHeight(8))
            .background(
                isFinished
                    ? Color("General/Feedback/Warning/Border").opacity(0.3)
                    : Color("General/LiveActivity/Secondary")
            )
            .cornerRadius(8.5)
        }
    }

    private func accessibilityLabel(isFinished: Bool) -> String {
        if showsCreatingIndicator { return "타이머 생성 중" }
        if isFinished { return "타이머 삭제" }
        return timer.status == .running ? "타이머 일시정지" : "타이머 재개"
    }

    private func progress(at date: Date) -> Double {
        guard timer.durationSeconds > 0 else { return 0 }
        let remaining = timerInterval.upperBound.timeIntervalSince(date)
        return min(1, max(0, remaining / Double(timer.durationSeconds)))
    }
}

private struct TimerRingView: View {
    let progress: Double
    let isFinished: Bool

    var body: some View {
        let lineWidth = WatchScreenMetrics.scaledHeight(1.5)

        ZStack {
            Circle()
                .stroke(
                    isFinished
                        ? Color("General/Timer/Identity/04")
                        : Color("General/Label/Primary"),
                    lineWidth: lineWidth
                )
            if progress > 0 {
                Circle()
                    .trim(from: 1 - progress, to: 1)
                    .stroke(
                        Color("General/Timer/Identity/04"),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt)
                    )
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: 30 - lineWidth, height: 30 - lineWidth)
        .frame(width: 30, height: 30)
        .allowsHitTesting(false)
    }
}

#Preview("실행 중") {
    RunningTimerView(
        timer: WatchTimerSnapshot(
            id: UUID(), durationSeconds: 60, remainingSeconds: 60,
            status: .running, measuredAt: .now
        ),
        isCommandPending: false, onPause: {}, onResume: {}, onDelete: {}
    )
}

#Preview("일시정지") {
    RunningTimerView(
        timer: WatchTimerSnapshot(
            id: UUID(), durationSeconds: 90, remainingSeconds: 42,
            status: .paused, measuredAt: .now
        ),
        isCommandPending: false, onPause: {}, onResume: {}, onDelete: {}
    )
}

#Preview("완료") {
    RunningTimerView(
        timer: WatchTimerSnapshot(
            id: UUID(), durationSeconds: 30, remainingSeconds: 0,
            status: .finished, measuredAt: .now
        ),
        isCommandPending: false, onPause: {}, onResume: {}, onDelete: {}
    )
}
