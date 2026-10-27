import AVFoundation
import Foundation
import QuartzCore
import Vision

nonisolated final class CameraHandDetector: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private enum Pose: Equatable {
        case fist
        case oneFinger
    }

    private let onHold: @Sendable (CameraHandEvent) -> Void
    private let request = VNDetectHumanHandPoseRequest()
    private var candidate: Pose?
    private var candidateStart: CFTimeInterval?
    private var lastDetection: CFTimeInterval?
    private var didEmit = false

    init(onHold: @escaping @Sendable (CameraHandEvent) -> Void) {
        self.onHold = onHold
        super.init()
        request.maximumHandCount = 1
    }

    func reset() {
        candidate = nil
        candidateStart = nil
        lastDetection = nil
        didEmit = false
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let pose: Pose?
        do {
            try VNImageRequestHandler(cmSampleBuffer: sampleBuffer).perform([request])
            pose = request.results?.first.flatMap(Self.classify)
        } catch {
            pose = nil
        }
        updateHold(for: pose, at: CACurrentMediaTime())
    }

    private func updateHold(for pose: Pose?, at now: CFTimeInterval) {
        guard let pose else {
            if let lastDetection, now - lastDetection >= 0.45 { reset() }
            return
        }

        if candidate != pose || lastDetection.map({ now - $0 >= 0.45 }) ?? true {
            candidate = pose
            candidateStart = now
            didEmit = false
        }
        lastDetection = now

        guard !didEmit, now - (candidateStart ?? now) >= 1 else { return }
        didEmit = true
        switch pose {
        case .fist: onHold(.fistHeld(.now))
        case .oneFinger: onHold(.oneFingerHeld(.now))
        }
    }

    private static func classify(_ hand: VNHumanHandPoseObservation) -> Pose? {
        guard let points = try? hand.recognizedPoints(.all),
              let wrist = points[.wrist], wrist.confidence >= 0.3 else { return nil }

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
        var extended = 0
        var indexExtended = false
        for (index, finger) in fingers.enumerated() {
            let (tipName, pipName, mcpName) = finger
            guard let tip = points[tipName], let pip = points[pipName], let mcp = points[mcpName],
                  min(tip.confidence, pip.confidence, mcp.confidence) >= 0.3 else { continue }
            visible += 1
            let palmLength = distance(wrist.location, mcp.location)
            let isExtended = distance(tip.location, wrist.location)
                >= distance(pip.location, wrist.location) + palmLength * 0.3
            if isExtended {
                extended += 1
                if index == 0 { indexExtended = true }
            } else {
                curled += 1
            }
        }

        if indexExtended, extended == 1, curled >= 2 { return .oneFinger }
        if visible >= 3, curled >= 3, extended == 0 { return .fist }
        return nil
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
