import Foundation
import LabcordiOS
import LabcordShared
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
            if let recording = PhoneWatchAudioService.shared.screenRecording,
               recording.experimentID == experimentID {
                Label(message(recording, at: context.date), systemImage: "applewatch")
                    .font(.caption.monospacedDigit())
                    .padding(8)
                    .background(.black.opacity(0.75), in: Capsule())
                    .foregroundStyle(.white)
            }
        }
        .padding(.top, 8)
        .allowsHitTesting(false)
    }

    private func message(_ recording: WatchScreenRecording, at date: Date) -> String {
        let duration = recording.elapsedSeconds.map { value in
            let seconds = max(0, Int(value))
            return " \(seconds / 60):\(String(format: "%02d", seconds % 60))"
        } ?? ""
        switch recording.phase {
        case .capturing: return "Watch 녹음 준비 중"
        case .recording:
            guard let live = PhoneWatchAudioService.shared.liveRecording,
                  live.recordingID == recording.id, date < live.expiresAt else {
                return "Watch 녹음 상태 확인 중"
            }
            let seconds = max(0, Int(date.timeIntervalSince(live.startedAt)))
            return "Watch 녹음 \(seconds / 60):\(String(format: "%02d", seconds % 60))"
        case .previewing, .review: return "Watch 음성\(duration) · 확인 중"
        case .saving: return "Watch 음성\(duration) · 저장 중"
        case .saved: return "Watch 음성\(duration) · 저장됨"
        case .failed: return "Watch 음성\(duration) · 처리 실패"
        case .cancelled: return "Watch 기록 취소됨"
        }
    }

}
