import AVFoundation
import QuartzCore
import Vision

nonisolated final class CameraHandDetector: NSObject,
                                            AVCaptureVideoDataOutputSampleBufferDelegate,
                                            @unchecked Sendable {
    private let onHold: @Sendable (CameraHandEvent) -> Void
    private let onTips: @Sendable (CameraHandOverlayHub.Frame) -> Void
    private let request = VNDetectHumanHandPoseRequest()
    private var holdTracker = HandHoldTracker()

    init(
        onHold: @escaping @Sendable (CameraHandEvent) -> Void,
        onTips: @escaping @Sendable (CameraHandOverlayHub.Frame) -> Void
    ) {
        self.onHold = onHold
        self.onTips = onTips
        super.init()
        request.maximumHandCount = 1
    }

    func reset() {
        holdTracker.reset()
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let analysis: HandPoseClassifier.Analysis?
        do {
            try VNImageRequestHandler(cmSampleBuffer: sampleBuffer).perform([request])
            analysis = request.results?.first.flatMap(HandPoseClassifier.analyze)
        } catch {
            analysis = nil
        }

        let imageSize: CGSize
        if let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            imageSize = CGSize(
                width: CVPixelBufferGetWidth(imageBuffer),
                height: CVPixelBufferGetHeight(imageBuffer)
            )
        } else {
            imageSize = .zero
        }
        onTips(CameraHandOverlayHub.Frame(
            tips: analysis?.extendedTips ?? [],
            imageSize: imageSize,
            videoRotationAngle: connection.videoRotationAngle,
            isVideoMirrored: connection.isVideoMirrored
        ))
        guard let heldPose = holdTracker.update(analysis?.pose, at: CACurrentMediaTime()) else {
            return
        }
        switch heldPose {
        case .openHand: onHold(.openHandHeld(.now))
        case .fist: onHold(.fistHeld(.now))
        case .oneFinger: onHold(.oneFingerHeld(.now))
        case .threeFingers: onHold(.threeFingersHeld(.now))
        }
    }
}
