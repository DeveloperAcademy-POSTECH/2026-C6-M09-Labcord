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

    var body: some View {
        if mode == .procedure {
            ProtocolModeTimerView(
                timers: timers,
                protocolTimerSeconds: protocolTimerSeconds
            )
        } else {
            FreeModeTimerView(timers: timers)
        }
    }
}

#Preview("자유모드") {
    ExperimentTimerView(mode: .free, timers: [], protocolTimerSeconds: [])
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
        protocolTimerSeconds: []
    )
}

#Preview("프로토콜모드") {
    ExperimentTimerView(
        mode: .procedure,
        timers: [],
        protocolTimerSeconds: [30, 90, 3_600]
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
        protocolTimerSeconds: [30, 90, 3_600]
    )
}
