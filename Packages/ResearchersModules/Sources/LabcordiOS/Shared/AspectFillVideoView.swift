import AVFoundation
import SwiftUI

public struct AspectFillVideoView: UIViewRepresentable {
    private let player: AVPlayer

    public init(player: AVPlayer) {
        self.player = player
    }

    public func makeUIView(context: Context) -> UIView {
        let view = PlayerView()
        view.playerLayer?.player = player
        view.playerLayer?.videoGravity = .resizeAspectFill
        return view
    }

    public func updateUIView(_ uiView: UIView, context: Context) {
        (uiView.layer as? AVPlayerLayer)?.player = player
    }
}

private final class PlayerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer? { layer as? AVPlayerLayer }
}
