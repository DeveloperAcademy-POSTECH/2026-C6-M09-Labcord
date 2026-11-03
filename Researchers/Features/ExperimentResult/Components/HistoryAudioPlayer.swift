import AVFoundation
import LabcordDesignSystem
import SwiftUI

struct HistoryAudioPlayer: View {
    let url: URL
    let recordID: UUID
    @Binding var activeMediaID: UUID?
    @Environment(\.scenePhase) private var scenePhase
    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var progress = 0.0
    @State private var isSeeking = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing4) {
            VoicePlayer(
                duration: durationText, isPlaying: $isPlaying, progress: $progress,
                onEditingChanged: { isSeeking = $0 },
                onToggle: toggle,
                onSeek: seek
            )
            .disabled(player == nil)
            if let errorMessage {
                Text(errorMessage).typography(Typography.subheadline)
            }
        }
        .task(id: url) {
            prepare()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(200)) } catch { break }
                if let player {
                    isPlaying = player.isPlaying
                    if !isSeeking, player.duration > 0 {
                        progress = player.currentTime / player.duration
                    }
                }
            }
        }
        .onDisappear {
            player?.stop()
            player = nil
            isPlaying = false
            if activeMediaID == recordID {
                try? AVAudioSession.sharedInstance().setActive(
                    false, options: .notifyOthersOnDeactivation
                )
                activeMediaID = nil
            }
        }
        .onChange(of: activeMediaID) { _, id in
            if id != recordID {
                player?.pause()
                isPlaying = false
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                player?.pause()
                isPlaying = false
            }
        }
    }

    private var durationText: String {
        guard let player else { return "--:--" }
        let seconds = max(0, Int(player.duration))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func prepare() {
        player?.stop()
        isPlaying = false
        progress = 0
        do {
            let loaded = try AVAudioPlayer(contentsOf: url)
            guard loaded.prepareToPlay() else { throw PlaybackError.unavailable }
            player = loaded
            errorMessage = nil
        } catch {
            player = nil
            errorMessage = "음성을 불러오지 못했어요."
        }
    }

    private func toggle() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
        } else {
            do {
                activeMediaID = recordID
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                try AVAudioSession.sharedInstance().setActive(true)
                if player.currentTime >= player.duration { player.currentTime = 0 }
                guard player.play() else { throw PlaybackError.unavailable }
                errorMessage = nil
            } catch {
                errorMessage = "음성을 재생하지 못했어요."
            }
        }
        isPlaying = player.isPlaying
    }

    private func seek(_ fraction: Double) {
        guard let player else { return }
        player.currentTime = min(max(fraction, 0), 1) * player.duration
        progress = fraction
    }

    private enum PlaybackError: Error {
        case unavailable
    }
}
