import Foundation
import Vision

nonisolated enum HandPoseClassifier {
    struct Analysis {
        let pose: HandPose?
        let extendedTips: [CGPoint]
    }

    private enum FingerBend {
        case curled
        case extended
    }

    private struct FingerJoints {
        let tip: VNHumanHandPoseObservation.JointName
        let middle: VNHumanHandPoseObservation.JointName
        let base: VNHumanHandPoseObservation.JointName
    }

    private static let confidenceThreshold: Float = 0.3
    private static let extensionMarginRatio: CGFloat = 0.3
    private static let thumbExtensionMarginRatio: CGFloat = 0.15
    private static let fingers: [FingerJoints] = [
        .init(tip: .indexTip, middle: .indexPIP, base: .indexMCP),
        .init(tip: .middleTip, middle: .middlePIP, base: .middleMCP),
        .init(tip: .ringTip, middle: .ringPIP, base: .ringMCP),
        .init(tip: .littleTip, middle: .littlePIP, base: .littleMCP)
    ]

    static func analyze(_ hand: VNHumanHandPoseObservation) -> Analysis? {
        guard let points = try? hand.recognizedPoints(.all),
              let wrist = points[.wrist], wrist.confidence >= confidenceThreshold,
              let indexMCP = points[.indexMCP], indexMCP.confidence >= confidenceThreshold,
              let littleMCP = points[.littleMCP],
              littleMCP.confidence >= confidenceThreshold else {
            return nil
        }

        let thumbTip = points[.thumbTip]
        let thumbBend: FingerBend?
        if let thumbTip,
           let thumbIP = points[.thumbIP],
           let thumbMP = points[.thumbMP] {
            thumbBend = bend(
                tip: thumbTip,
                middle: thumbIP,
                base: thumbMP,
                anchor: littleMCP.location,
                extensionMargin: distance(indexMCP.location, littleMCP.location)
                    * thumbExtensionMarginRatio
            )
        } else {
            thumbBend = nil
        }

        var curled = thumbBend == .curled ? 1 : 0
        var extended = thumbBend == .extended ? 1 : 0
        var isComplete = thumbBend != nil
        var extendedTips: [CGPoint] = []
        if thumbBend == .extended, let thumbTip {
            extendedTips.append(thumbTip.location)
        }
        for finger in fingers {
            guard let tip = points[finger.tip],
                  let pip = points[finger.middle],
                  let mcp = points[finger.base] else {
                isComplete = false
                continue
            }
            guard let fingerBend = bend(
                      tip: tip,
                      middle: pip,
                      base: mcp,
                      anchor: wrist.location,
                      extensionMargin: distance(wrist.location, mcp.location)
                          * extensionMarginRatio
                  ) else {
                isComplete = false
                continue
            }
            if fingerBend == .extended {
                extended += 1
                extendedTips.append(tip.location)
            } else {
                curled += 1
            }
        }

        let pose: HandPose?
        if !isComplete {
            pose = nil
        } else if extended == 5 {
            pose = .openHand
        } else if curled == 5 {
            pose = .fist
        } else if extended == 1, curled == 4 {
            pose = .oneFinger
        } else if extended == 3, curled == 2 {
            pose = .threeFingers
        } else {
            pose = nil
        }
        return Analysis(pose: pose, extendedTips: extendedTips)
    }

    private static func bend(
        tip: VNRecognizedPoint,
        middle: VNRecognizedPoint,
        base: VNRecognizedPoint,
        anchor: CGPoint,
        extensionMargin: CGFloat
    ) -> FingerBend? {
        guard min(tip.confidence, middle.confidence, base.confidence) >= confidenceThreshold else {
            return nil
        }

        let reach = distance(tip.location, anchor) - distance(middle.location, anchor)
        if reach <= 0 { return .curled }
        if reach >= extensionMargin { return .extended }
        return nil
    }

    private static func distance(_ firstPoint: CGPoint, _ secondPoint: CGPoint) -> CGFloat {
        hypot(firstPoint.x - secondPoint.x, firstPoint.y - secondPoint.y)
    }
}
