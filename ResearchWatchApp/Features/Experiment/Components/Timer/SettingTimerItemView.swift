//
//  SettingTimerItemView.swift
//  ResearchWatch Watch App
//
//  Created by 정홍섭 on 11/17/26.
//

import LabcordDesignSystem
import LabcordShared
import LabcordWatchOS
import SwiftUI

struct SettingTimerItemView: View {
    let seconds: Int
    let onStart: () -> Void

    private var durationComponents: TimerDurationFormatter.Components {
        TimerDurationFormatter.components(magnitude: UInt64(max(0, seconds)))
    }

    var body: some View {
        Button(action: onStart) {
            VStack(alignment: .center, spacing: 0) {
                Text(durationComponents.value)
                    .font(.title3)
                    .lineLimit(1)

                Text(durationComponents.unit)
                    .font(.title3)
            }
            .frame(
                width: WatchScreenMetrics.scaledHeight(68),
                height: WatchScreenMetrics.scaledHeight(68)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(durationComponents.text)
        }
        .buttonBorderShape(.circle)
        .overlay {
            Circle()
                .strokeBorder(
                    Color("General/Timer/Identity/04"),
                    lineWidth: WatchScreenMetrics.scaledHeight(2)
                )
                .allowsHitTesting(false)
        }
        .padding(.vertical, -WatchScreenMetrics.scaledHeight(4))
    }
}

#Preview {
    SettingTimerItemView(seconds: 30) {}
}
