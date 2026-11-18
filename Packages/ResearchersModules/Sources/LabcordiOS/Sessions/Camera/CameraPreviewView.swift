//
//  CameraPreviewView.swift
//  labcord-package-swift
//
//  Created by 정홍섭 on 10/26/26.
//

import SwiftUI
import UIKit
#if DEBUG && targetEnvironment(simulator)
import AVFoundation

public struct RecordingDemoCapturePosition {
    public let url: URL
    public let time: CMTime
    public let previewSize: CGSize
}

/// Controls the simulator-only recording preview; this does not capture video or detect gestures.
@MainActor
public enum RecordingDemoVideoPreview {
    private static let notification = Notification.Name("LabcordRecordingDemoVideoChanged")
    private static var selectedURL: URL?
    private static var hasSelection = false
    private static var selectionID = UUID()
    private static var triggered = false
    private static weak var capturePlayer: AVPlayer?
    private static weak var captureLayer: AVPlayerLayer?
    private static var captureURL: URL?
    private static var capturePlaybackID = UUID()
    public static var onTrigger: (@MainActor @Sendable (String) -> Void)?

    static func speechPlayback() -> RecordingDemoSpeechPlayback? {
        guard hasSelection, let selectedURL, selectedURL == captureURL,
              let capturePlayer,
              let scene = RecordingDemoSpeechScene(fileName: selectedURL.lastPathComponent) else {
            return nil
        }
        return RecordingDemoSpeechPlayback(
            selectionID: selectionID, playbackID: capturePlaybackID,
            scene: scene, seconds: capturePlayer.currentTime().seconds
        )
    }

    public static func capturePosition() -> RecordingDemoCapturePosition? {
        guard let capturePlayer, let captureLayer, let captureURL else { return nil }
        return RecordingDemoCapturePosition(
            url: captureURL,
            time: capturePlayer.currentTime(),
            previewSize: captureLayer.bounds.size
        )
    }

    fileprivate static func attachPlayer(_ player: AVPlayer, layer: AVPlayerLayer, url: URL) {
        capturePlayer = player
        captureLayer = layer
        captureURL = url
        capturePlaybackID = UUID()
    }

    fileprivate static func detachPlayer(_ player: AVPlayer?) {
        guard let player, capturePlayer === player else { return }
        capturePlayer = nil
        captureLayer = nil
        captureURL = nil
    }

    public static func select(url: URL?) {
        selectedURL = url
        hasSelection = true
        selectionID = UUID()
        triggered = false
        NotificationCenter.default.post(name: notification, object: nil)
    }

    fileprivate static func observe(
        _ change: @escaping @MainActor @Sendable () -> Void
    ) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: notification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in change() }
        }
    }

    fileprivate static var currentURL: URL? { selectedURL }
    fileprivate static var hasSelectedVideo: Bool { hasSelection }
    fileprivate static var currentSelectionID: UUID { selectionID }

    fileprivate static func trigger(_ action: String, selection: UUID) {
        guard selectionID == selection, !triggered else { return }
        triggered = true
        onTrigger?(action)
    }
}
#endif

public struct CameraPreviewView: UIViewRepresentable {
    public let connector: CameraPreviewConnector
    public let showsHandOverlay: Bool

    public init(connector: CameraPreviewConnector, showsHandOverlay: Bool = true) {
        self.connector = connector
        self.showsHandOverlay = showsHandOverlay
    }

    public func makeUIView(context: Context) -> some UIView {
        let view = PreviewUIView()
        #if targetEnvironment(simulator)
        view.backgroundColor = .green
        #if DEBUG
        view.startRecordingDemoPreview()
        #endif
        #else
        view.connector = connector
        connector.attach(to: view, showsHandOverlay: showsHandOverlay)
        #endif
        return view
    }

    public func updateUIView(_ uiView: UIViewType, context: Context) {
        guard let view = uiView as? PreviewUIView else { return }
        #if !targetEnvironment(simulator)
        if view.connector != connector {
            view.connector?.detach(from: view)
        }
        view.connector = connector
        connector.attach(to: view, showsHandOverlay: showsHandOverlay)
        #endif
    }

    public static func dismantleUIView(_ uiView: UIViewType, coordinator: ()) {
        guard let view = uiView as? PreviewUIView else { return }
        #if DEBUG && targetEnvironment(simulator)
        view.stopRecordingDemoPreview()
        #endif
        view.connector?.detach(from: view)
        view.connector = nil
    }
}

private final class PreviewUIView: UIView {
    var connector: CameraPreviewConnector?
    #if DEBUG && targetEnvironment(simulator)
    private var demoPlayer: AVPlayer?
    private var demoLayer: AVPlayerLayer?
    private var demoObserver: NSObjectProtocol?
    private var demoTimeObserver: Any?
    private var demoPlaybackID = UUID()
    private let demoPoster: UIImageView = {
        let view = UIImageView()
        if let url = Bundle.module.url(forResource: "RecordingDemoPoster", withExtension: "jpg") {
            view.image = UIImage(contentsOfFile: url.path)
        }
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        return view
    }()

    func startRecordingDemoPreview() {
        addSubview(demoPoster)
        demoObserver = RecordingDemoVideoPreview.observe { [weak self] in
            self?.updateRecordingDemoPreview()
        }
        updateRecordingDemoPreview()
    }

    private func updateRecordingDemoPreview() {
        demoPlaybackID = UUID()
        removeDemoTimeObserver()
        RecordingDemoVideoPreview.detachPlayer(demoPlayer)
        demoPlayer?.pause()
        demoLayer?.removeFromSuperlayer()
        demoPlayer = nil
        demoLayer = nil
        let isInitialPreview = !RecordingDemoVideoPreview.hasSelectedVideo
        demoPoster.isHidden = !isInitialPreview && RecordingDemoVideoPreview.currentURL == nil
        let initialURL = URL.documentsDirectory.appending(path: "LabcordDemoVideos/V03.mp4")
        let selectedURL = isInitialPreview ? initialURL : RecordingDemoVideoPreview.currentURL
        guard let url = selectedURL,
              FileManager.default.isReadableFile(atPath: url.path) else { return }
        let player = AVPlayer(url: url)
        player.isMuted = true
        player.actionAtItemEnd = .pause
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        layer.frame = bounds
        self.layer.addSublayer(layer)
        demoPlayer = player
        demoLayer = layer
        RecordingDemoVideoPreview.attachPlayer(player, layer: layer, url: url)
        if isInitialPreview {
            playInitialPreview(player)
            return
        }
        configureDemoTrigger(player, url: url)
        player.play()
    }

    private func configureDemoTrigger(_ player: AVPlayer, url: URL) {
        let fileName = url.deletingPathExtension().lastPathComponent.uppercased()
        let name = [
            "V06-A-PLUS-B": "V06-A", "W02_DOUBLE_PINCH": "V06-A",
            "W03_SINGLE_FIST": "V07", "W04_DOUBLE_FIST": "V08"
        ][fileName] ?? fileName
        let frames: [String: Int64] = [
            "V03": 48, "V04": 64, "V05": 60, "V06-A": 114,
            "V07": 42, "V08": 57, "V12": 70, "W02_DOUBLE_PINCH": 25,
            "W03_SINGLE_FIST": 28, "W04_DOUBLE_FIST": 35
        ]
        let frame = frames[fileName] ?? frames[name]
        if let frame {
            let selection = RecordingDemoVideoPreview.currentSelectionID
            let playback = demoPlaybackID
            let time = CMTime(value: frame, timescale: 24)
            demoTimeObserver = player.addBoundaryTimeObserver(
                forTimes: [NSValue(time: time)], queue: .main
            ) { [weak self] in
                Task { @MainActor in
                    guard self?.demoPlaybackID == playback else { return }
                    RecordingDemoVideoPreview.trigger(name, selection: selection)
                }
            }
        }
    }

    private func playInitialPreview(_ player: AVPlayer) {
        let playback = demoPlaybackID
        player.play()
        Task { @MainActor [weak self, weak player] in
            try? await Task.sleep(for: .seconds(1))
            guard self?.demoPlaybackID == playback else { return }
            player?.pause()
        }
    }

    private func removeDemoTimeObserver() {
        if let demoTimeObserver, let demoPlayer {
            demoPlayer.removeTimeObserver(demoTimeObserver)
        }
        demoTimeObserver = nil
    }

    func stopRecordingDemoPreview() {
        demoPlaybackID = UUID()
        if let demoObserver { NotificationCenter.default.removeObserver(demoObserver) }
        demoObserver = nil
        removeDemoTimeObserver()
        RecordingDemoVideoPreview.detachPlayer(demoPlayer)
        demoPlayer?.pause()
        demoPlayer = nil
        demoLayer?.removeFromSuperlayer()
        demoLayer = nil
    }
    #endif

    override func layoutSubviews() {
        super.layoutSubviews()
        connector?.updateLayout(in: self)
        #if DEBUG && targetEnvironment(simulator)
        demoPoster.frame = bounds
        demoLayer?.frame = bounds
        #endif
    }
}
