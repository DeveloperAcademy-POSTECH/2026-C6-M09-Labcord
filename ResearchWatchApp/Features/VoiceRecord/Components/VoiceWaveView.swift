//
//  VoiceWaveView.swift
//  Researchers
//
//  Created by 정홍섭 on 11/17/26.
//

import Foundation
import LabcordDesignSystem
import LabcordWatchOS
import SwiftUI

struct VoiceWaveView: View {
    let isVoiceDetected: Bool

    private let bars: [(width: CGFloat, height: CGFloat)] = [
        (2.77, 18), (4, 26), (4, 40), (4, 50),
        (4, 40), (4, 26), (2.77, 18)
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !isVoiceDetected)) { context in
            HStack(alignment: .center, spacing: WatchScreenMetrics.scaledWidth(6)) {
                ForEach(bars.indices, id: \.self) { index in
                    Rectangle()
                        .frame(
                            width: WatchScreenMetrics.scaledWidth(bars[index].width),
                            height: WatchScreenMetrics.scaledHeight(
                                height(for: index, at: context.date)
                            )
                        )
                        .cornerRadius(.infinity)
                        .frame(maxHeight: WatchScreenMetrics.scaledHeight(bars[index].height))
                }
            }
            .frame(height: WatchScreenMetrics.scaledHeight(50))
            .foregroundStyle(Color("General/Brand/Primary"))
        }
        .animation(.easeOut(duration: 0.28), value: isVoiceDetected)
    }

    private func height(for index: Int, at date: Date) -> CGFloat {
        guard isVoiceDetected else { return bars[index].height }
        let seconds = date.timeIntervalSinceReferenceDate
        let offset = Double(index) * 1.7
        let motion = 0.5
            + 0.42 * sin(seconds * (7.3 + Double(index) * 0.8) + offset)
            + 0.28 * sin(seconds * (3.4 + Double(index) * 0.35) + offset * 1.8)
        let progress = min(1, max(0, motion))
        return 1 + (bars[index].height - 1) * CGFloat(progress)
    }
}

#Preview {
    VoiceWaveView(isVoiceDetected: true)
}
