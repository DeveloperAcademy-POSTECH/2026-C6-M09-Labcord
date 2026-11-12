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

    init(
        session: AVCaptureSession,
        device: AVCaptureDevice?,
        handOverlayHub: CameraHandOverlayHub
    ) {
        self.storage = CameraPreviewStorage(
            session: session,
            device: device,
            handOverlayHub: handOverlayHub
        )
    }

    @MainActor
    public func attach(to view: UIView, showsHandOverlay: Bool = true) {
        storage.attach(to: view, showsHandOverlay: showsHandOverlay)
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
    private let handOverlayHub: CameraHandOverlayHub
    private var device: AVCaptureDevice?

    @MainActor private var previewLayer: AVCaptureVideoPreviewLayer?
    @MainActor private var skeletonLayer: CAShapeLayer?
    @MainActor private var overlayTask: Task<Void, Never>?
    @MainActor private var showsHandOverlay = true
    @MainActor private var latestFrame = CameraHandOverlayHub.Frame(
        segments: [],
        joints: [],
        imageSize: .zero,
        videoRotationAngle: 0,
        isVideoMirrored: false
    )
    @MainActor private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    @MainActor private var rotationObservation: NSKeyValueObservation?

    init(
        session: AVCaptureSession,
        device: AVCaptureDevice?,
        handOverlayHub: CameraHandOverlayHub
    ) {
        self.session = session
        self.device = device
        self.handOverlayHub = handOverlayHub
    }

    @MainActor
    func attach(to view: UIView, showsHandOverlay: Bool) {
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
        let skeleton: CAShapeLayer
        if let skeletonLayer {
            skeleton = skeletonLayer
        } else {
            skeleton = CAShapeLayer()
            skeleton.strokeColor = UIColor.white.cgColor
            skeleton.fillColor = UIColor.white.cgColor
            skeleton.lineWidth = 1.5
            skeleton.lineCap = .round
            skeletonLayer = skeleton
        }
        if skeleton.superlayer !== view.layer {
            view.layer.addSublayer(skeleton)
        }
        view.clipsToBounds = true
        updateHandOverlayVisibility(showsHandOverlay)
        updateLayout(in: view)

        configureRotationIfNeeded(for: layer)
    }

    @MainActor
    func updateDevice(_ device: AVCaptureDevice) {
        guard self.device !== device else { return }
        self.device = device
        rotationObservation = nil
        rotationCoordinator = nil
        latestFrame = .init(
            segments: [], joints: [], imageSize: .zero,
            videoRotationAngle: 0, isVideoMirrored: false
        )
        drawSkeleton()
        if let previewLayer {
            configureRotationIfNeeded(for: previewLayer)
        }
    }

    @MainActor
    func detach(from view: UIView) {
        guard previewLayer?.superlayer === view.layer else { return }
        rotationObservation = nil
        rotationCoordinator = nil
        overlayTask?.cancel()
        overlayTask = nil
        latestFrame = .init(
            segments: [], joints: [], imageSize: .zero,
            videoRotationAngle: 0, isVideoMirrored: false
        )
        skeletonLayer?.removeFromSuperlayer()
        skeletonLayer = nil
        previewLayer?.removeFromSuperlayer()
        previewLayer = nil
    }

    @MainActor
    func updateLayout(in view: UIView) {
        guard let previewLayer, previewLayer.superlayer === view.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.frame = view.bounds
        skeletonLayer?.frame = view.bounds
        drawSkeleton()
        CATransaction.commit()
    }

    @MainActor
    private func drawSkeleton() {
        guard let previewLayer, let skeletonLayer else { return }
        guard showsHandOverlay else {
            skeletonLayer.path = nil
            return
        }
        let path = UIBezierPath()
        for segment in latestFrame.segments {
            guard let start = previewPoint(for: segment.start, in: previewLayer),
                  let end = previewPoint(for: segment.end, in: previewLayer) else { continue }
            path.move(to: start)
            path.addLine(to: end)
        }
        for joint in latestFrame.joints {
            guard let point = previewPoint(for: joint, in: previewLayer) else { continue }
            path.append(UIBezierPath(ovalIn: CGRect(
                x: point.x - 2,
                y: point.y - 2,
                width: 4,
                height: 4
            )))
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        skeletonLayer.path = path.cgPath
        CATransaction.commit()
    }

    @MainActor
    private func updateHandOverlayVisibility(_ isVisible: Bool) {
        showsHandOverlay = isVisible
        skeletonLayer?.isHidden = !isVisible
        guard isVisible else {
            overlayTask?.cancel()
            overlayTask = nil
            latestFrame = .init(
                segments: [], joints: [], imageSize: .zero,
                videoRotationAngle: 0, isVideoMirrored: false
            )
            skeletonLayer?.path = nil
            return
        }
        guard overlayTask == nil else { return }
        overlayTask = Task { @MainActor [weak self, handOverlayHub] in
            for await frame in handOverlayHub.stream() {
                guard !Task.isCancelled, let self, self.showsHandOverlay else { continue }
                self.latestFrame = frame
                self.drawSkeleton()
            }
        }
    }

    @MainActor
    private func previewPoint(
        for joint: CGPoint,
        in layer: AVCaptureVideoPreviewLayer
    ) -> CGPoint? {
        guard let connection = layer.connection,
              latestFrame.imageSize.width > 0,
              latestFrame.imageSize.height > 0 else { return nil }

        let dataTurns = quarterTurns(for: latestFrame.videoRotationAngle)
        let previewTurns = quarterTurns(for: connection.videoRotationAngle)
        var point = CGPoint(x: joint.x, y: 1 - joint.y)
        if latestFrame.isVideoMirrored {
            point.x = 1 - point.x
        }
        point = rotate(point, quarterTurns: (4 - dataTurns) % 4)
        point = rotate(point, quarterTurns: previewTurns)
        if connection.isVideoMirrored {
            point.x = 1 - point.x
        }

        let dataSize = latestFrame.imageSize
        let rawSize = dataTurns.isMultiple(of: 2)
            ? dataSize
            : CGSize(width: dataSize.height, height: dataSize.width)
        let previewSize = previewTurns.isMultiple(of: 2)
            ? rawSize
            : CGSize(width: rawSize.height, height: rawSize.width)
        let scale = max(
            layer.bounds.width / previewSize.width,
            layer.bounds.height / previewSize.height
        )
        let imageWidth = previewSize.width * scale
        let imageHeight = previewSize.height * scale
        return CGPoint(
            x: (layer.bounds.width - imageWidth) / 2 + point.x * imageWidth,
            y: (layer.bounds.height - imageHeight) / 2 + point.y * imageHeight
        )
    }

    private func quarterTurns(for angle: CGFloat) -> Int {
        let turns = Int((angle / 90).rounded())
        return (turns % 4 + 4) % 4
    }

    private func rotate(_ point: CGPoint, quarterTurns: Int) -> CGPoint {
        switch quarterTurns {
        case 1: return CGPoint(x: 1 - point.y, y: point.x)
        case 2: return CGPoint(x: 1 - point.x, y: 1 - point.y)
        case 3: return CGPoint(x: point.y, y: 1 - point.x)
        default: return point
        }
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
        drawSkeleton()
    }
}
