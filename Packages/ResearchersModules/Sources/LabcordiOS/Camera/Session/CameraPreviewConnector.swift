//
//  CameraPreviewConnector.swift
//  labcord-package-swift
//
//  Created by 정홍섭 on 10/26/26.
//

import AVFoundation
import Foundation
import UIKit

nonisolated public struct CameraPreviewConnector: @unchecked Sendable {
    private let session: AVCaptureSession
    private let storage: CameraPreviewStorage

    init(session: AVCaptureSession, device: AVCaptureDevice?) {
        self.session = session
        self.storage = CameraPreviewStorage(session: session, device: device)
    }

    @MainActor
    public func attach(to view: UIView) {
        storage.attach(to: view)
    }

    @MainActor
    public func detach() {
        storage.detach()
    }

    @MainActor
    public func updateLayout(in view: UIView) {
        storage.updateLayout(in: view)
    }
}

extension CameraPreviewConnector: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.storage === rhs.storage
    }
}

nonisolated private final class CameraPreviewStorage: @unchecked Sendable {
    private let session: AVCaptureSession
    private let device: AVCaptureDevice?

    @MainActor private var previewLayer: AVCaptureVideoPreviewLayer?
    @MainActor private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    @MainActor private var rotationObservation: NSKeyValueObservation?

    init(session: AVCaptureSession, device: AVCaptureDevice?) {
        self.session = session
        self.device = device
    }

    @MainActor
    func attach(to view: UIView) {
        let layer: AVCaptureVideoPreviewLayer
        if let previewLayer {
            layer = previewLayer
        } else {
            layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            previewLayer = layer
        }

        if layer.superlayer !== view.layer {
            view.layer.addSublayer(layer)
        }
        view.clipsToBounds = true
        updateLayout(in: view)

        if rotationCoordinator == nil, let device {
            let coordinator = AVCaptureDevice.RotationCoordinator(
                device: device,
                previewLayer: layer
            )
            rotationCoordinator = coordinator
            rotationObservation = coordinator.observe(
                \.videoRotationAngleForHorizonLevelPreview,
                options: [.new]
            ) { [weak self] coordinator, _ in
                MainActor.assumeIsolated {
                    self?.applyRotation(
                        coordinator.videoRotationAngleForHorizonLevelPreview
                    )
                }
            }
        }

        if let rotationCoordinator {
            applyRotation(rotationCoordinator.videoRotationAngleForHorizonLevelPreview)
        }
    }

    @MainActor
    func detach() {
        rotationObservation = nil
        rotationCoordinator = nil
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil
    }

    @MainActor
    func updateLayout(in view: UIView) {
        guard let previewLayer, previewLayer.superlayer === view.layer else { return }
        previewLayer.frame = view.bounds
    }

    @MainActor
    private func applyRotation(_ angle: CGFloat) {
        guard let connection = previewLayer?.connection,
              connection.isVideoRotationAngleSupported(angle),
              connection.videoRotationAngle != angle else { return }
        connection.videoRotationAngle = angle
    }
}
