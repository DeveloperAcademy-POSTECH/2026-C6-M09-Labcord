//
//  FreeModeTimerView.swift
//  ResearchWatch Watch App
//
//  Created by 정홍섭 on 11/17/26.
//

import SwiftUI
import LabcordShared

struct FreeModeTimerView: View {
    let timers: [WatchTimerSnapshot]

    private var hasRunningTimer: Bool {
        timers.contains { $0.status == .running }
    }

    var body: some View {
        if hasRunningTimer {
            ProgressTimerView()
        } else {
            Text("현재 진행 중인\n타이머가 없어요.")
                .multilineTextAlignment(.center)
        }
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
        ]
    )
}

#Preview("없음") {
    FreeModeTimerView(timers: [])
}
