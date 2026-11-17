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

    private var hasRunningTimer: Bool {
        timers.contains { $0.status == .running }
    }

    var body: some View {
        if hasRunningTimer {
            ProgressTimerView()
        } else {
            SettingTimerView(timerSeconds: protocolTimerSeconds)
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
        protocolTimerSeconds: [30, 90]
    )
}

#Preview("없음") {
    ProtocolModeTimerView(timers: [], protocolTimerSeconds: [30, 90, 3_600])
}
