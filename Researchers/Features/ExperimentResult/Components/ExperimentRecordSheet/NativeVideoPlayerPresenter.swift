import AVFoundation
import AVKit
import Foundation
import SwiftUI
import UIKit

struct NativeVideoPlayerPresenter: UIViewControllerRepresentable {
    let player: AVPlayer?
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> PresentationController {
        PresentationController()
    }

    func updateUIViewController(_ controller: PresentationController, context: Context) {
        controller.configure(player: player, onDismiss: onDismiss)
    }

    final class PresentationController: UIViewController,
        AVPlayerViewControllerDelegate, UIAdaptivePresentationControllerDelegate {
        private var player: AVPlayer?
        private var onDismiss: (() -> Void)?
        private var hasPresentedPlayer = false
        private weak var presentedPlayerController: AVPlayerViewController?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            if hasPresentedPlayer, presentedViewController == nil {
                finishPresentation()
            } else {
                presentPlayerIfNeeded()
            }
        }

        func configure(player: AVPlayer?, onDismiss: @escaping () -> Void) {
            self.player = player
            self.onDismiss = onDismiss
            DispatchQueue.main.async { [weak self] in
                self?.presentPlayerIfNeeded()
            }
        }

        private func presentPlayerIfNeeded() {
            guard view.window != nil,
                  let player,
                  presentedViewController == nil else { return }

            let controller = AVPlayerViewController()
            controller.player = player
            controller.delegate = self
            controller.showsPlaybackControls = true
            controller.allowsPictureInPicturePlayback = false
            controller.videoGravity = .resizeAspect
            controller.overrideUserInterfaceStyle = .dark
            controller.view.tintColor = .white
            controller.modalPresentationStyle = .fullScreen
            hasPresentedPlayer = true
            presentedPlayerController = controller
            present(controller, animated: false) {
                controller.presentationController?.delegate = self
            }
        }

        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            willEndFullScreenPresentationWithAnimationCoordinator coordinator:
                any UIViewControllerTransitionCoordinator
        ) {
            coordinator.animate(alongsideTransition: nil) { [weak self] context in
                if !context.isCancelled { self?.finishPresentation() }
            }
        }

        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            restoreUserInterfaceForFullScreenExitWithCompletionHandler completionHandler:
                @escaping @Sendable (Bool) -> Void
        ) {
            completionHandler(true)
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            finishPresentation()
        }

        private func finishPresentation() {
            guard player != nil else { return }
            presentedPlayerController?.player = nil
            presentedPlayerController = nil
            player = nil
            hasPresentedPlayer = false
            onDismiss?()
        }
    }
}
