import AVFoundation
import Foundation

final class RecordedAudioPlayer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.researchers.result.audio-player")
    private var player: AVAudioPlayer?

    func prepare(url: URL) async -> TimeInterval? {
        await withCheckedContinuation { continuation in
            queue.async {
                self.player = try? AVAudioPlayer(contentsOf: url)
                self.player?.prepareToPlay()
                continuation.resume(returning: self.player?.duration)
            }
        }
    }

    func play() async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async {
                guard let player = self.player else {
                    continuation.resume(returning: false)
                    return
                }
                do {
                    let audioSession = AVAudioSession.sharedInstance()
                    try audioSession.setCategory(.playback)
                    try audioSession.setActive(true)
                    if player.currentTime >= player.duration {
                        player.currentTime = 0
                    }
                    continuation.resume(returning: player.play())
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }

    func pause() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.player?.pause()
                continuation.resume()
            }
        }
    }

    func stop() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.player?.stop()
                continuation.resume()
            }
        }
    }

    func seek(to value: Double) async {
        await withCheckedContinuation { continuation in
            queue.async {
                if let player = self.player {
                    player.currentTime = player.duration * min(max(value, 0), 1)
                }
                continuation.resume()
            }
        }
    }

    func snapshot() async -> (progress: Double, isPlaying: Bool) {
        await withCheckedContinuation { continuation in
            queue.async {
                guard let player = self.player else {
                    continuation.resume(returning: (0, false))
                    return
                }
                let progress = player.duration > 0 ? player.currentTime / player.duration : 0
                continuation.resume(returning: (progress, player.isPlaying))
            }
        }
    }
}
