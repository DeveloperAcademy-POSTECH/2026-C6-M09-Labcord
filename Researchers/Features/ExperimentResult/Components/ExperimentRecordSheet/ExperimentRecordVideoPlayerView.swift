import AVFoundation
import Combine
import Foundation
import LabcordDesignSystem
import SwiftUI

struct ExperimentRecordVideoPlayerView: View {
    private final class Playback: ObservableObject {
        let player: AVPlayer
        let item: AVPlayerItem

        init(url: URL) {
            item = AVPlayerItem(url: url)
            player = AVPlayer(playerItem: item)
            player.allowsExternalPlayback = false
        }
    }

    let url: URL
    let isFullScreen: Bool
    let onOpenFullScreen: (AVPlayer) -> Void

    @StateObject private var playback: Playback
    @State private var duration: TimeInterval = 0

    init(url: URL, isFullScreen: Bool, onOpenFullScreen: @escaping (AVPlayer) -> Void) {
        self.url = url
        self.isFullScreen = isFullScreen
        self.onOpenFullScreen = onOpenFullScreen
        _playback = StateObject(wrappedValue: Playback(url: url))
    }

    var body: some View {
        ZStack {
            if isFullScreen {
                Color.black
            } else {
                inlinePlayer
                    .contentShape(Rectangle())
                    .onTapGesture { onOpenFullScreen(playback.player) }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint(Text("전체 화면으로 엽니다"))
            }
        }
        .task(id: url) {
            let asset = AVURLAsset(url: url)
            guard let time = try? await asset.load(.duration), !Task.isCancelled else { return }
            let seconds = time.seconds
            duration = seconds.isFinite ? max(0, seconds) : 0
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: AVPlayerItem.didPlayToEndTimeNotification,
                object: playback.item
            )
        ) { _ in
            playback.player.seek(to: .zero)
            playback.player.play()
        }
        .onAppear { playback.player.play() }
        .onChange(of: isFullScreen) { wasFullScreen, isFullScreen in
            if wasFullScreen, !isFullScreen { playback.player.play() }
        }
        .onDisappear {
            if !isFullScreen { playback.player.pause() }
        }
    }

    private var inlinePlayer: some View {
        ZStack(alignment: .bottom) {
            AspectFillVideoView(player: playback.player)
                .allowsHitTesting(false)

            playbackOverlay
        }
        .accessibilityLabel(Text("자동 반복 재생 중인 영상"))
    }

    private var playbackOverlay: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [.clear, .black.opacity(0.35)],
                startPoint: .center,
                endPoint: .bottom
            )
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                let elapsed = playback.player.currentTime().seconds
                let currentTime = elapsed.isFinite ? max(0, elapsed) : 0

                HStack(spacing: 12) {
                    Text(timeLabel(currentTime))
                        .typography(Typography.caption2)
                        .foregroundStyle(.gray)

                    GeometryReader { geometry in
                        Capsule()
                            .fill(.white.opacity(0.45))
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(.white)
                                    .frame(width: geometry.size.width * progress(at: currentTime))
                            }
                    }
                    .frame(height: 4)

                    Text(timeLabel(duration))
                        .typography(Typography.caption2)
                        .foregroundStyle(.gray)
                }
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .allowsHitTesting(false)
            }
        }
        .allowsHitTesting(false)
    }

    private func progress(at currentTime: TimeInterval) -> CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(min(currentTime / duration, 1))
    }

    private func timeLabel(_ time: TimeInterval) -> String {
        let seconds = Int(time)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
