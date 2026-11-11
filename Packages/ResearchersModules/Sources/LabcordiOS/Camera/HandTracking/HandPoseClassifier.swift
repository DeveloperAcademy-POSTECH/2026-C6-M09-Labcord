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
        let tip: CGPoint?
    }

    private struct FingerSummary {
        var curled = 0
        var extended = 0
        var extendedTips: [CGPoint] = []

        mutating func add(_ detection: FingerDetection?) {
            guard let detection else { return }
            switch detection.bend {
            case .curled:
                curled += 1
            case .extended:
                extended += 1
                if let tip = detection.tip { extendedTips.append(tip) }
            }
        }
    }

    private struct FingerJoints {
        let tip: HumanHandPoseObservation.JointName
        let distal: HumanHandPoseObservation.JointName
        let middle: HumanHandPoseObservation.JointName
        let base: HumanHandPoseObservation.JointName
    }

    private static let confidenceThreshold: Float = 0.3
    private static let extensionMarginRatio: CGFloat = 0.3
    private static let thumbExtensionMarginRatio: CGFloat = 0.15
    private static let fingers: [FingerJoints] = [
        .init(tip: .indexTip, distal: .indexDIP, middle: .indexPIP, base: .indexMCP),
        .init(tip: .middleTip, distal: .middleDIP, middle: .middlePIP, base: .middleMCP),
        .init(tip: .ringTip, distal: .ringDIP, middle: .ringPIP, base: .ringMCP),
        .init(tip: .littleTip, distal: .littleDIP, middle: .littlePIP, base: .littleMCP)
    ]

    static func analyze(_ hand: HumanHandPoseObservation) -> Analysis? {
        let points = hand.allJoints()
        guard let wrist = points[.wrist], wrist.confidence >= confidenceThreshold,
              let indexMCP = points[.indexMCP], indexMCP.confidence >= confidenceThreshold,
              let littleMCP = points[.littleMCP],
              littleMCP.confidence >= confidenceThreshold else {
            return nil
        }

        var summary = FingerSummary()
        summary.add(thumbDetection(
            in: points,
            indexMCP: indexMCP.location.cgPoint,
            littleMCP: littleMCP.location.cgPoint
        ))
        for finger in fingers {
            summary.add(fingerDetection(finger, in: points, wrist: wrist.location.cgPoint))
        }

        return Analysis(pose: pose(for: summary), extendedTips: summary.extendedTips)
    }

    private static func thumbDetection(
        in points: [HumanHandPoseObservation.JointName: Joint],
        indexMCP: CGPoint,
        littleMCP: CGPoint
    ) -> FingerDetection? {
        guard let middle = points[.thumbIP],
              let base = points[.thumbMP],
              base.confidence >= confidenceThreshold else { return nil }
        return detection(
            tip: points[.thumbTip],
            distal: middle,
            middle: middle,
            fallbackMiddle: base,
            anchor: littleMCP,
            extensionMargin: distance(indexMCP, littleMCP) * thumbExtensionMarginRatio
        )
    }

    private static func fingerDetection(
        _ finger: FingerJoints,
        in points: [HumanHandPoseObservation.JointName: Joint],
        wrist: CGPoint
    ) -> FingerDetection? {
        guard let middle = points[finger.middle],
              let base = points[finger.base],
              base.confidence >= confidenceThreshold else { return nil }
        return detection(
            tip: points[finger.tip],
            distal: points[finger.distal],
            middle: middle,
            anchor: wrist,
            extensionMargin: distance(wrist, base.location.cgPoint) * extensionMarginRatio
        )
    }

    private static func detection(
        tip: Joint?,
        distal: Joint?,
        middle: Joint,
        fallbackMiddle: Joint? = nil,
        anchor: CGPoint,
        extensionMargin: CGFloat
    ) -> FingerDetection? {
        if let tip, tip.confidence >= confidenceThreshold {
            guard let fingerBend = bend(
                tip: tip,
                middle: middle,
                anchor: anchor,
                extensionMargin: extensionMargin
            ) else { return nil }
            return FingerDetection(bend: fingerBend, tip: tip.location.cgPoint)
        }

        guard let distal,
              let fingerBend = bend(
                  tip: distal,
                  middle: fallbackMiddle ?? middle,
                  anchor: anchor,
                  extensionMargin: extensionMargin * 0.5
              ) else { return nil }
        return FingerDetection(bend: fingerBend, tip: nil)
    }

    private static func pose(for summary: FingerSummary) -> HandPose? {
        guard summary.curled + summary.extended == 5 else { return nil }
        if summary.extended == 5 { return .openHand }
        if summary.curled == 5 { return .fist }
        if summary.extended == 1, summary.curled == 4 { return .oneFinger }
        if summary.extended == 3, summary.curled == 2 { return .threeFingers }
        return nil
    }

    private static func bend(
        tip: Joint,
        middle: Joint,
        anchor: CGPoint,
        extensionMargin: CGFloat
    ) -> FingerBend? {
        guard min(tip.confidence, middle.confidence) >= confidenceThreshold else {
            return nil
        }

        let reach = distance(tip.location.cgPoint, anchor)
            - distance(middle.location.cgPoint, anchor)
        if reach <= 0 { return .curled }
        if reach >= extensionMargin { return .extended }
        return nil
    }

    private static func distance(_ firstPoint: CGPoint, _ secondPoint: CGPoint) -> CGFloat {
        hypot(firstPoint.x - secondPoint.x, firstPoint.y - secondPoint.y)
    }
}
