import LabcordDesignSystem
import SwiftUI

struct RecordedAudioTimelineView: View {
    let url: URL

    @State private var audioPlayer = RecordedAudioPlayer()
    @State private var duration: TimeInterval?
    @State private var isPlaying = false
    @State private var progress = 0.0
    @State private var isSeeking = false
    @State private var loadFailed = false
    @State private var playbackFailed = false
    @State private var playbackTask: Task<Void, Never>?

    var body: some View {
        Group {
            if let duration {
                VStack(alignment: .leading, spacing: LayoutTokens.spacing8) {
                    VoicePlayer(
                        duration: durationText(duration),
                        isPlaying: $isPlaying,
                        progress: $progress,
                        onEditingChanged: { isSeeking = $0 },
                        onToggle: togglePlayback,
                        onSeek: seek
                    )
                    if playbackFailed {
                        Text("음성을 재생할 수 없습니다. 다시 시도해 주세요.")
                    }
                }
            } else if loadFailed {
                Text("음성 파일을 불러올 수 없습니다.")
            } else {
                ProgressView()
            }
        }
        .task(id: url) {
            let preparedDuration = await audioPlayer.prepare(url: url)
            guard !Task.isCancelled else { return }
            duration = preparedDuration
            loadFailed = preparedDuration == nil
        }
        .task(id: isPlaying) {
            guard isPlaying else { return }
            while !Task.isCancelled && isPlaying {
                let snapshot = await audioPlayer.snapshot()
                guard !Task.isCancelled else { return }
                if !isSeeking {
                    progress = snapshot.progress
                }
                if !snapshot.isPlaying {
                    isPlaying = false
                    break
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        .onDisappear {
            playbackTask?.cancel()
            playbackTask = nil
            Task { await audioPlayer.stop() }
            isPlaying = false
        }
    }

    private func togglePlayback() {
        guard duration != nil else { return }
        if isPlaying {
            isPlaying = false
            Task { await audioPlayer.pause() }
        } else {
            guard playbackTask == nil else { return }
            playbackFailed = false
            playbackTask = Task {
                let started = await audioPlayer.play()
                guard !Task.isCancelled else { return }
                playbackTask = nil
                isPlaying = started
                playbackFailed = !started
            }
        }
    }

    private func seek(_ value: Double) {
        Task { await audioPlayer.seek(to: value) }
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let seconds = Int(duration)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
