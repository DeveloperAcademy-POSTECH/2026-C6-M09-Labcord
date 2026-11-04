//
//  PhotoCaptureCountdownView.swift
//  Researchers
//
//  Created by 정홍섭 on 11/4/26.
//

import LabcordDesignSystem
import SwiftUI

struct PhotoCaptureCountdownView: View {
    let endsAt: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { context in
            let remaining = max(0, endsAt.timeIntervalSince(context.date))
            let seconds = Int(ceil(remaining))

            ProgressRing(value: remaining / 5, showPercentage: false, centerText: "\(seconds)")
        }
    }
}

#Preview {
    PhotoCaptureCountdownView(endsAt: .now.addingTimeInterval(5))
}
