import Foundation
import LabcordShared
import SwiftUI

struct WatchMirroredRecordingView: View {
    let recording: WatchScreenRecording
    let isCurrent: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 32))
                    .foregroundStyle(.blue)
                Text(title)
                    .font(.headline)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    if let end = recording.countdownEndsAt {
                        let seconds = max(0, Int(ceil(end.timeIntervalSince(context.date))))
                        Text(seconds > 0 ? "촬영까지 \(seconds)초" : "촬영 결과 확인 중")
                            .monospacedDigit()
                    } else if let elapsed = WatchPresentationRules.recordingDuration(
                        recording, at: context.date
                    ) {
                        Text(WatchPresentationRules.formatDuration(elapsed))
                            .monospacedDigit()
                    }
                }
                Text(isCurrent ? "iPhone에서 기록을 조작해주세요." : "연결 후 상태를 다시 확인해요.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 8)
        }
    }

    private var symbol: String {
        switch recording.kind {
        case .audio: "waveform"
        case .photo: "camera.fill"
        case .video: "video.fill"
        }
    }

    private var title: String {
        switch recording.phase {
        case .capturing, .recording:
            switch recording.kind {
            case .audio: "iPhone 음성 녹음 중"
            case .photo: "iPhone 사진 촬영 중"
            case .video: "iPhone 영상 녹화 중"
            }
        case .previewing: "iPhone에서 미리보기 중"
        case .review: "iPhone에서 기록 확인 중"
        case .saving: "iPhone에서 저장 중"
        case .saved: "기록 저장 완료"
        case .failed: "iPhone에서 기록 상태를 확인해주세요."
        case .cancelled: "기록 취소됨"
        }
    }
}
