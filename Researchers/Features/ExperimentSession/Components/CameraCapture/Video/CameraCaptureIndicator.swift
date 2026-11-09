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

struct WatchVoiceRecordingIndicator: View {
    let experimentID: UUID

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let recording = PhoneWatchAudioService.shared.liveRecording,
               recording.experimentID == experimentID, context.date < recording.expiresAt {
                let seconds = max(0, Int(context.date.timeIntervalSince(recording.startedAt)))
                Label("워치 녹음 \(seconds / 60):\(String(format: "%02d", seconds % 60))",
                      systemImage: "mic.fill")
                    .font(.caption.monospacedDigit())
                    .padding(8)
                    .background(.black.opacity(0.75), in: Capsule())
                    .foregroundStyle(.white)
            }
        }
        .padding(.top, 8)
        .allowsHitTesting(false)
    }
}
