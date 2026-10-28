import AVFoundation
import QuartzCore
import Vision

nonisolated final class CameraHandDetector: NSObject,
                                            AVCaptureVideoDataOutputSampleBufferDelegate,
                                            @unchecked Sendable {
    private let onHold: @Sendable (CameraHandEvent) -> Void
    private let request = VNDetectHumanHandPoseRequest()
    private var holdTracker = HandHoldTracker()

    init(onHold: @escaping @Sendable (CameraHandEvent) -> Void) {
        self.onHold = onHold
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
        let pose: HandPose?
        do {
            try VNImageRequestHandler(cmSampleBuffer: sampleBuffer).perform([request])
            pose = request.results?.first.flatMap(HandPoseClassifier.classify)
        } catch {
            pose = nil
        }

        guard let heldPose = holdTracker.update(pose, at: CACurrentMediaTime()) else { return }
        switch heldPose {
        case .openHand: onHold(.openHandHeld(.now))
        case .fist: onHold(.fistHeld(.now))
        case .oneFinger: onHold(.oneFingerHeld(.now))
        case .threeFingers: onHold(.threeFingersHeld(.now))
        }
    }
}
