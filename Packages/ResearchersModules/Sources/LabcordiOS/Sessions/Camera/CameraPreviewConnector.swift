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
    private let storage: CameraPreviewStorage

    init(session: AVCaptureSession, device: AVCaptureDevice?) {
        self.storage = CameraPreviewStorage(session: session, device: device)
    }

    @MainActor
    public func attach(to view: UIView) {
        storage.attach(to: view)
    }

    @MainActor
    public func detach(from view: UIView) {
        storage.detach(from: view)
    }

    @MainActor
    public func updateLayout(in view: UIView) {
        storage.updateLayout(in: view)
    }

    @MainActor
    public func updateDevice(_ device: AVCaptureDevice) {
        storage.updateDevice(device)
    }
}

extension CameraPreviewConnector: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.storage === rhs.storage
    }
}

nonisolated private final class CameraPreviewStorage: @unchecked Sendable {
    private let session: AVCaptureSession
    private var device: AVCaptureDevice?

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

        configureRotationIfNeeded(for: layer)
    }

    @MainActor
    func updateDevice(_ device: AVCaptureDevice) {
        guard self.device !== device else { return }
        self.device = device
        rotationObservation = nil
        rotationCoordinator = nil
        if let previewLayer {
            configureRotationIfNeeded(for: previewLayer)
        }
    }

    @MainActor
    func detach(from view: UIView) {
        guard previewLayer?.superlayer === view.layer else { return }
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
    private func configureRotationIfNeeded(for layer: AVCaptureVideoPreviewLayer) {
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
    private func applyRotation(_ angle: CGFloat) {
        guard let connection = previewLayer?.connection,
              connection.isVideoRotationAngleSupported(angle),
              connection.videoRotationAngle != angle else { return }
        connection.videoRotationAngle = angle
    }
}
