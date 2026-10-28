import Foundation
import LabcordiOS
import SwiftUI

struct VideoRecordingIndicator: View {
    let startedAt: Date

    var body: some View {
        TimelineView(.periodic(from: startedAt, by: 0.1)) { timeline in
            let seconds = min(
                VideoRecordingSettings.durationSeconds,
                max(0, Int(timeline.date.timeIntervalSince(startedAt)))
            )
            HStack(spacing: 10) {
                Circle()
                    .fill(.red)
                    .frame(width: 20, height: 20)

                Text(String(format: "00:%02d", seconds))
                    .font(.default)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.8), radius: 2)
            }
        }
    }
}
