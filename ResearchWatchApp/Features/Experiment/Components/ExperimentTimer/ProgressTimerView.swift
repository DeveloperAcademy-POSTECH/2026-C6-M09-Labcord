//
//  ProgressTimerView.swift
//  ResearchWatch Watch App
//
//  Created by 정홍섭 on 11/17/26.
//

import LabcordShared
import LabcordWatchOS
import SwiftUI

struct ProgressTimerView: View {
    let timers: [WatchTimerSnapshot]
    let pendingTimerIDs: Set<UUID>
    var creatingTimerIDs: Set<UUID> = []
    let onTimerCommand: (UUID, WatchExperimentCommand.Operation) -> Void

    var showsTitle = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsTitle {
                Text("진행 중인 타이머")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.bottom, WatchScreenMetrics.scaledHeight(4))
                    .padding(.horizontal, WatchScreenMetrics.scaledWidth(9.5))
            }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 4) {
                    ForEach(sortedTimers(at: context.date)) { timer in
                        RunningTimerView(
                            timer: timer,
                            isCommandPending: pendingTimerIDs.contains(timer.id),
                            isCreating: creatingTimerIDs.contains(timer.id),
                            onPause: { onTimerCommand(timer.id, .pauseTimer) },
                            onResume: { onTimerCommand(timer.id, .resumeTimer) },
                            onDelete: { onTimerCommand(timer.id, .deleteTimer) }
                        )
                        .padding(.horizontal, WatchScreenMetrics.scaledWidth(0.5))
                    }
                }
            }
            .ignoresSafeArea()
        }
    }

    private func sortedTimers(at date: Date) -> [WatchTimerSnapshot] {
        timers.sorted { left, right in
            let leftRemaining = left.remaining(at: date)
            let rightRemaining = right.remaining(at: date)
            if leftRemaining != rightRemaining { return leftRemaining < rightRemaining }
            let leftStartedAt = left.startedAt ?? left.measuredAt
            let rightStartedAt = right.startedAt ?? right.measuredAt
            if leftStartedAt != rightStartedAt { return leftStartedAt < rightStartedAt }
            return left.id.uuidString < right.id.uuidString
        }
    }
}

#Preview {
    ProgressTimerView(
        timers: [
            WatchTimerSnapshot(
                id: UUID(), durationSeconds: 30, remainingSeconds: 26,
                status: .running, measuredAt: .now
            ),
            WatchTimerSnapshot(
                id: UUID(), durationSeconds: 90, remainingSeconds: 42,
                status: .paused, measuredAt: .now
            )
        ],
        pendingTimerIDs: []
    ) { _, _ in }
}
