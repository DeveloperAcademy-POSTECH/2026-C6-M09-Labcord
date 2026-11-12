import AVFoundation
import Dispatch
import QuartzCore
import Vision

nonisolated final class CameraHandDetector: NSObject,
                                            AVCaptureVideoDataOutputSampleBufferDelegate,
                                            @unchecked Sendable {
    private let onHold: @Sendable (CameraHandEvent) -> Void
    private let onOverlay: @Sendable (CameraHandOverlayHub.Frame) -> Void
    private let queue: DispatchQueue
    private var holdTracker = HandHoldTracker()
    private var processingTask: Task<Void, Never>?
    private var generation = 0

    init(
        queue: DispatchQueue,
        onHold: @escaping @Sendable (CameraHandEvent) -> Void,
        onOverlay: @escaping @Sendable (CameraHandOverlayHub.Frame) -> Void
    ) {
        self.queue = queue
        self.onHold = onHold
        self.onOverlay = onOverlay
        super.init()
    }

    func reset() {
        generation += 1
        processingTask?.cancel()
        processingTask = nil
        holdTracker.reset()
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard processingTask == nil else { return }
        let generation = generation
        let imageSize: CGSize
        if let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            imageSize = CGSize(
                width: CVPixelBufferGetWidth(imageBuffer),
                height: CVPixelBufferGetHeight(imageBuffer)
            )
        } else {
            imageSize = .zero
        }
        let frame = CameraHandOverlayHub.Frame(
            segments: [],
            joints: [],
            imageSize: imageSize,
            videoRotationAngle: connection.videoRotationAngle,
            isVideoMirrored: connection.isVideoMirrored
        )
        processingTask = Task { [self] in
            var request = DetectHumanHandPoseRequest()
            request.maximumHandCount = 1
            let observations = try? await request.perform(on: sampleBuffer)
            let analysis = observations?.first.flatMap(HandPoseClassifier.analyze)
            queue.async { [self] in
                guard self.generation == generation else { return }
                processingTask = nil
                process(analysis, frame: frame)
            }
        }
    }

    private func process(
        _ analysis: HandPoseClassifier.Analysis?,
        frame: CameraHandOverlayHub.Frame
    ) {
        onOverlay(CameraHandOverlayHub.Frame(
            segments: analysis?.segments ?? [],
            joints: analysis?.joints ?? [],
            imageSize: frame.imageSize,
            videoRotationAngle: frame.videoRotationAngle,
            isVideoMirrored: frame.isVideoMirrored
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
