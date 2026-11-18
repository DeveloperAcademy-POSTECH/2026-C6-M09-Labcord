//
//  ExperimentTimerView.swift
//  Researchers
//
//  Created by 정홍섭 on 11/17/26.
//

import LabcordShared
import SwiftUI

struct ExperimentTimerView: View {
    let mode: ExperimentMode?
    let timers: [WatchTimerSnapshot]
    let protocolTimerSeconds: [Int]
    let pendingTimerIDs: Set<UUID>
    var creatingTimerIDs: Set<UUID> = []
    let onTimerCommand: (UUID, WatchExperimentCommand.Operation) -> Void
    let onStartTimer: (Int) -> Void
    let onAddTimer: () -> Void

    var body: some View {
        if mode == .procedure {
            ProtocolModeTimerView(
                timers: timers,
                protocolTimerSeconds: protocolTimerSeconds,
                pendingTimerIDs: pendingTimerIDs,
                creatingTimerIDs: creatingTimerIDs,
                onTimerCommand: onTimerCommand,
                onStartTimer: onStartTimer,
                onAddTimer: onAddTimer
            )
        } else {
            FreeModeTimerView(
                timers: timers, pendingTimerIDs: pendingTimerIDs,
                creatingTimerIDs: creatingTimerIDs, onTimerCommand: onTimerCommand
            )
        }
    }
}

#Preview("자유모드") {
    ExperimentTimerView(
        mode: .free, timers: [], protocolTimerSeconds: [],
        pendingTimerIDs: [], onTimerCommand: { _, _ in }, onStartTimer: { _ in },
        onAddTimer: {}
    )
}

#Preview("자유모드(타이머)") {
    ExperimentTimerView(
        mode: .free,
        timers: [
            WatchTimerSnapshot(
                id: UUID(),
                durationSeconds: 600,
                remainingSeconds: 300,
                status: .running,
                measuredAt: .now
            )
        ],
        protocolTimerSeconds: [],
        pendingTimerIDs: [], onTimerCommand: { _, _ in }, onStartTimer: { _ in },
        onAddTimer: {}
    )
}

#Preview("프로토콜모드") {
    ExperimentTimerView(
        mode: .procedure,
        timers: [],
        protocolTimerSeconds: [30, 90, 3_600],
        pendingTimerIDs: [], onTimerCommand: { _, _ in }, onStartTimer: { _ in },
        onAddTimer: {}
    )
}

#Preview("프로토콜모드(타이머)") {
    ExperimentTimerView(
        mode: .procedure,
        timers: [
            WatchTimerSnapshot(
                id: UUID(),
                durationSeconds: 600,
                remainingSeconds: 300,
                status: .running,
                measuredAt: .now
            )
        ],
        protocolTimerSeconds: [30, 90, 3_600],
        pendingTimerIDs: [], onTimerCommand: { _, _ in }, onStartTimer: { _ in },
        onAddTimer: {}
    )
}
