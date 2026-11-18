//
//  FreeModeTimerView.swift
//  ResearchWatch Watch App
//
//  Created by 정홍섭 on 11/17/26.
//

import LabcordDesignSystem
import LabcordShared
import LabcordWatchOS
import SwiftUI

struct FreeModeTimerView: View {
    let timers: [WatchTimerSnapshot]
    let pendingTimerIDs: Set<UUID>
    var creatingTimerIDs: Set<UUID> = []
    let onTimerCommand: (UUID, WatchExperimentCommand.Operation) -> Void

    private var hasTimers: Bool {
        !timers.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WatchScreenMetrics.scaledHeight(8)) {
                Text("진행 중인 타이머")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(
                        height: WatchScreenMetrics.scaledHeight(16),
                        alignment: .topLeading
                    )

                if hasTimers {
                    ProgressTimerView(
                        timers: timers, pendingTimerIDs: pendingTimerIDs,
                        creatingTimerIDs: creatingTimerIDs,
                        onTimerCommand: onTimerCommand, showsTitle: false
                    )
                } else {
                    Text("현재 진행 중인\n타이머가 없어요.")
                        .foregroundStyle(Color(.Colors.Labels.secondary))
                        .frame(maxWidth: .infinity)
                        .padding(.top, WatchScreenMetrics.scaledHeight(8))
                        .font(.system(size: 15, weight: .regular))
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, hasTimers ? 0 : 9.5)
    }
}

#Preview("진행 중") {
    FreeModeTimerView(
        timers: [
            WatchTimerSnapshot(
                id: UUID(),
                durationSeconds: 600,
                remainingSeconds: 300,
                status: .running,
                measuredAt: .now
            )
        ],
        pendingTimerIDs: [], onTimerCommand: { _, _ in }
    )
}

#Preview("없음") {
    FreeModeTimerView(timers: [], pendingTimerIDs: [], onTimerCommand: { _, _ in })
}
