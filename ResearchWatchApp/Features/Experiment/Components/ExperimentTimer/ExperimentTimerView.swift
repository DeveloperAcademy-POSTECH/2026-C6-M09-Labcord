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

    var body: some View {
        if mode == .procedure {
            ProtocolModeTimerView(timers: timers)
        } else {
            FreeModeTimerView(timers: timers)
        }
    }
}

#Preview("자유모드") {
    ExperimentTimerView(mode: .free, timers: [])
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
        ]
    )
}

#Preview("프로토콜모드") {
    ExperimentTimerView(mode: .procedure, timers: [])
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
        ]
    )
}
