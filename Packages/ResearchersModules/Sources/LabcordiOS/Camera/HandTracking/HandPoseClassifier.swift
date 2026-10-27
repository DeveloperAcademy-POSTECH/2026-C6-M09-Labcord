import Foundation
import Vision

nonisolated enum HandPoseClassifier {
    private static let confidenceThreshold: Float = 0.3
    private static let curlMarginRatio: CGFloat = 0.3
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
              let wrist = points[.wrist], wrist.confidence >= confidenceThreshold else {
            return nil
        }

        var visible = 0
        var curled = 0
        var extended = 0
        var indexExtended = false
        for (index, finger) in fingers.enumerated() {
            let (tipName, pipName, mcpName) = finger
            guard let tip = points[tipName], let pip = points[pipName], let mcp = points[mcpName],
                  min(tip.confidence, pip.confidence, mcp.confidence) >= confidenceThreshold else {
                continue
            }
            visible += 1
            let palmLength = distance(wrist.location, mcp.location)
            let isExtended = distance(tip.location, wrist.location)
                >= distance(pip.location, wrist.location) + palmLength * curlMarginRatio
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
