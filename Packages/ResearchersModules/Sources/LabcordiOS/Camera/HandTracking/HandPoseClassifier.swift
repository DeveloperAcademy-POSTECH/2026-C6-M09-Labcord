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

    private struct FingerDetection {
        let bend: FingerBend
        let tip: CGPoint
    }

    private struct FingerSummary {
        var curled = 0
        var extended = 0
        var isComplete = true
        var extendedTips: [CGPoint] = []

        mutating func add(_ detection: FingerDetection?) {
            guard let detection else {
                isComplete = false
                return
            }
            switch detection.bend {
            case .curled:
                curled += 1
            case .extended:
                extended += 1
                extendedTips.append(detection.tip)
            }
        }
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

        var summary = FingerSummary()
        summary.add(thumbDetection(
            in: points,
            indexMCP: indexMCP.location,
            littleMCP: littleMCP.location
        ))
        for finger in fingers {
            summary.add(fingerDetection(finger, in: points, wrist: wrist.location))
        }

        return Analysis(pose: pose(for: summary), extendedTips: summary.extendedTips)
    }

    private static func thumbDetection(
        in points: [VNHumanHandPoseObservation.JointName: VNRecognizedPoint],
        indexMCP: CGPoint,
        littleMCP: CGPoint
    ) -> FingerDetection? {
        guard let tip = points[.thumbTip],
              let middle = points[.thumbIP],
              let base = points[.thumbMP],
              let fingerBend = bend(
                  tip: tip,
                  middle: middle,
                  base: base,
                  anchor: littleMCP,
                  extensionMargin: distance(indexMCP, littleMCP) * thumbExtensionMarginRatio
              ) else { return nil }
        return FingerDetection(bend: fingerBend, tip: tip.location)
    }

    private static func fingerDetection(
        _ finger: FingerJoints,
        in points: [VNHumanHandPoseObservation.JointName: VNRecognizedPoint],
        wrist: CGPoint
    ) -> FingerDetection? {
        guard let tip = points[finger.tip],
              let middle = points[finger.middle],
              let base = points[finger.base],
              let fingerBend = bend(
                  tip: tip,
                  middle: middle,
                  base: base,
                  anchor: wrist,
                  extensionMargin: distance(wrist, base.location) * extensionMarginRatio
              ) else { return nil }
        return FingerDetection(bend: fingerBend, tip: tip.location)
    }

    private static func pose(for summary: FingerSummary) -> HandPose? {
        guard summary.isComplete else { return nil }
        if summary.extended == 5 { return .openHand }
        if summary.curled == 5 { return .fist }
        if summary.extended == 1, summary.curled == 4 { return .oneFinger }
        if summary.extended == 3, summary.curled == 2 { return .threeFingers }
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

    private static func distance(_ firstPoint: CGPoint, _ secondPoint: CGPoint) -> CGFloat {
        hypot(firstPoint.x - secondPoint.x, firstPoint.y - secondPoint.y)
    }
}
