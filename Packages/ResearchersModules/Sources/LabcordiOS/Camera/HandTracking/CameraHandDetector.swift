import AVFoundation
import Foundation
import QuartzCore
import Vision

nonisolated final class CameraHandDetector: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let onFistHeld: @Sendable () -> Void
    private let request = VNDetectHumanHandPoseRequest()
    private var fistStart: CFTimeInterval?
    private var didEmit = false

    init(onFistHeld: @escaping @Sendable () -> Void) {
        self.onFistHeld = onFistHeld
        super.init()
        request.maximumHandCount = 1
    }

    func reset() {
        fistStart = nil
        didEmit = false
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        do {
            try VNImageRequestHandler(cmSampleBuffer: sampleBuffer).perform([request])
            guard let hand = request.results?.first, Self.isFist(hand) else {
                reset()
                return
            }

            let now = CACurrentMediaTime()
            if fistStart == nil { fistStart = now }
            if !didEmit, now - (fistStart ?? now) >= 1 {
                didEmit = true
                onFistHeld()
            }
        } catch {
            reset()
        }
    }

    private static func isFist(_ hand: VNHumanHandPoseObservation) -> Bool {
        guard let points = try? hand.recognizedPoints(.all),
              let wrist = points[.wrist], wrist.confidence >= 0.3 else { return false }

        let fingers: [(VNHumanHandPoseObservation.JointName,
                       VNHumanHandPoseObservation.JointName,
                       VNHumanHandPoseObservation.JointName)] = [
            (.indexTip, .indexPIP, .indexMCP),
            (.middleTip, .middlePIP, .middleMCP),
            (.ringTip, .ringPIP, .ringMCP),
            (.littleTip, .littlePIP, .littleMCP)
        ]

        var visible = 0
        var curled = 0
        for (tipName, pipName, mcpName) in fingers {
            guard let tip = points[tipName], let pip = points[pipName], let mcp = points[mcpName],
                  min(tip.confidence, pip.confidence, mcp.confidence) >= 0.3 else { continue }
            visible += 1
            let palmLength = distance(wrist.location, mcp.location)
            if distance(tip.location, wrist.location)
                < distance(pip.location, wrist.location) + palmLength * 0.3 {
                curled += 1
            }
        }
        return visible >= 3 && curled >= 3
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}

