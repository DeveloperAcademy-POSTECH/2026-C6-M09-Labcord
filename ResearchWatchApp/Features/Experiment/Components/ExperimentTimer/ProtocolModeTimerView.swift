//
//  ProtocolModeTimerView.swift
//  ResearchWatch Watch App
//
//  Created by 정홍섭 on 11/17/26.
//

import Foundation
import LabcordShared
import SwiftUI

struct ProtocolModeTimerView: View {
    let timers: [WatchTimerSnapshot]
    let protocolTimerSeconds: [Int]
    let pendingTimerIDs: Set<UUID>
    var creatingTimerIDs: Set<UUID> = []
    let onTimerCommand: (UUID, WatchExperimentCommand.Operation) -> Void
    let onStartTimer: (Int) -> Void
    let onAddTimer: () -> Void

    private var hasTimers: Bool {
        !timers.isEmpty
    }

    var body: some View {
        if hasTimers {
            ScrollView {
                ProgressTimerView(
                    timers: timers, pendingTimerIDs: pendingTimerIDs,
                    creatingTimerIDs: creatingTimerIDs, onTimerCommand: onTimerCommand
                )
            }
        } else {
            SettingTimerView(
                timerSeconds: protocolTimerSeconds, onStart: onStartTimer, onAdd: onAddTimer
            )
        }
    }
}

#Preview("진행 중") {
    ProtocolModeTimerView(
        timers: [
            WatchTimerSnapshot(
                id: UUID(),
                durationSeconds: 600,
                remainingSeconds: 300,
                status: .running,
                measuredAt: .now
            )
        ],
        protocolTimerSeconds: [30, 90],
        pendingTimerIDs: [], onTimerCommand: { _, _ in }, onStartTimer: { _ in },
        onAddTimer: {}
    )
}

#Preview("없음") {
    ProtocolModeTimerView(
        timers: [], protocolTimerSeconds: [30, 90, 3_600],
        pendingTimerIDs: [], onTimerCommand: { _, _ in }, onStartTimer: { _ in },
        onAddTimer: {}
    )
}
