import Foundation
import Vision

nonisolated enum HandPoseClassifier {
    private enum FingerBend {
        case curled
        case extended
    }

    private static let confidenceThreshold: Float = 0.3
    private static let extensionMarginRatio: CGFloat = 0.3
    private static let thumbExtensionMarginRatio: CGFloat = 0.15
    private static let fingers: [(VNHumanHandPoseObservation.JointName,
                                  VNHumanHandPoseObservation.JointName,
                                  VNHumanHandPoseObservation.JointName)] = [
        (.indexTip, .indexPIP, .indexMCP),
        (.middleTip, .middlePIP, .middleMCP),
        (.ringTip, .ringPIP, .ringMCP),
        (.littleTip, .littlePIP, .littleMCP)
    ]

    static func classify(_ hand: VNHumanHandPoseObservation) -> HandPose? {
        guard let points = try? hand.recognizedPoints(.all),
              let wrist = points[.wrist], wrist.confidence >= confidenceThreshold,
              let indexMCP = points[.indexMCP], indexMCP.confidence >= confidenceThreshold,
              let littleMCP = points[.littleMCP], littleMCP.confidence >= confidenceThreshold,
              let thumbTip = points[.thumbTip],
              let thumbIP = points[.thumbIP],
              let thumbMP = points[.thumbMP],
              let thumbBend = bend(
                  tip: thumbTip,
                  middle: thumbIP,
                  base: thumbMP,
                  anchor: littleMCP.location,
                  extensionMargin: distance(indexMCP.location, littleMCP.location)
                      * thumbExtensionMarginRatio
              ) else {
            return nil
        }

        var curled = thumbBend == .curled ? 1 : 0
        var extended = thumbBend == .extended ? 1 : 0
        for finger in fingers {
            let (tipName, pipName, mcpName) = finger
            guard let tip = points[tipName], let pip = points[pipName], let mcp = points[mcpName],
                  let fingerBend = bend(
                      tip: tip,
                      middle: pip,
                      base: mcp,
                      anchor: wrist.location,
                      extensionMargin: distance(wrist.location, mcp.location)
                          * extensionMarginRatio
                  ) else {
                return nil
            }
            if fingerBend == .extended {
                extended += 1
            } else {
                curled += 1
            }
        }

        if extended == 5 { return .openHand }
        if curled == 5 { return .fist }
        if extended == 1, curled == 4 { return .oneFinger }
        return nil
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

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
