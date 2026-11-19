import Foundation
import Vision

nonisolated enum HandPoseClassifier {
    struct Analysis {
        let pose: HandPose?
        /// Vision에 전달한 방향 기준 정규 좌표(좌하단 원점)입니다.
        let segments: [CameraHandOverlayHub.Segment]
        let joints: [CGPoint]
        /// Vision에 전달한 방향 기준 픽셀 공간의 손목→중지 MCP 벡터입니다.
        let pointingDirection: CGVector?
    }

    private enum FingerState {
        case extended
        case curled
        case unknown
    }

    private struct FingerJoints {
        let tip: HumanHandPoseObservation.JointName
        let distal: HumanHandPoseObservation.JointName
        let middle: HumanHandPoseObservation.JointName
        let base: HumanHandPoseObservation.JointName
    }

    /// 픽셀 좌표로 변환한 신뢰 가능한 관절과 손바닥 길이입니다.
    private struct HandGeometry {
        let points: [HumanHandPoseObservation.JointName: CGPoint]
        let wrist: CGPoint
        let palmLength: CGFloat

        func reach(_ point: CGPoint) -> CGFloat {
            HandPoseClassifier.distance(point, wrist) / palmLength
        }
    }

    private static let confidenceThreshold: Float = 0.3
    private static let minimumPalmLength: CGFloat = 16
    /// 아래 값은 손바닥 길이(손목→중지 MCP) 단위입니다.
    private static let tipExtensionMargin: CGFloat = 0.25
    private static let distalExtensionMargin: CGFloat = 0.12
    private static let curledReachLimit: CGFloat = 1.0
    private static let thumbExtendedReach: CGFloat = 0.75
    private static let thumbTuckedReach: CGFloat = 0.55
    private static let fingers: [FingerJoints] = [
        .init(tip: .indexTip, distal: .indexDIP, middle: .indexPIP, base: .indexMCP),
        .init(tip: .middleTip, distal: .middleDIP, middle: .middlePIP, base: .middleMCP),
        .init(tip: .ringTip, distal: .ringDIP, middle: .ringPIP, base: .ringMCP),
        .init(tip: .littleTip, distal: .littleDIP, middle: .littlePIP, base: .littleMCP)
    ]
    private static let skeletonChains: [[HumanHandPoseObservation.JointName]] = [
        [.wrist, .thumbCMC, .thumbMP, .thumbIP, .thumbTip],
        [.wrist, .indexMCP, .indexPIP, .indexDIP, .indexTip],
        [.wrist, .middleMCP, .middlePIP, .middleDIP, .middleTip],
        [.wrist, .ringMCP, .ringPIP, .ringDIP, .ringTip],
        [.wrist, .littleMCP, .littlePIP, .littleDIP, .littleTip]
    ]

    /// - Parameter imageSize: Vision에 전달한 방향 기준 이미지 픽셀 크기입니다.
    ///   정규 좌표는 가로·세로를 각각 1로 맞춘 값이라 그대로 거리를 재면 방향마다 길이가 달라집니다.
    static func analyze(_ hand: HumanHandPoseObservation, imageSize: CGSize) -> Analysis {
        let visibleJoints = hand.allJoints().compactMapValues { joint in
            joint.confidence >= confidenceThreshold ? joint.location.cgPoint : nil
        }
        var segments: [CameraHandOverlayHub.Segment] = []
        for chain in skeletonChains {
            for (start, end) in zip(chain, chain.dropFirst()) {
                guard let startPoint = visibleJoints[start],
                      let endPoint = visibleJoints[end] else { continue }
                segments.append(.init(start: startPoint, end: endPoint))
            }
        }
        let joints = Array(visibleJoints.values)
        let points = visibleJoints.mapValues { point in
            CGPoint(x: point.x * imageSize.width, y: point.y * imageSize.height)
        }
        guard let wrist = points[.wrist], let middleMCP = points[.middleMCP],
              distance(wrist, middleMCP) >= minimumPalmLength else {
            return Analysis(pose: nil, segments: segments, joints: joints, pointingDirection: nil)
        }

        let geometry = HandGeometry(
            points: points,
            wrist: wrist,
            palmLength: distance(wrist, middleMCP)
        )
        let fingerStates = fingers.map { fingerState($0, in: geometry) }
        return Analysis(
            pose: pose(fingers: fingerStates, thumb: thumbState(in: geometry)),
            segments: segments,
            joints: joints,
            pointingDirection: CGVector(dx: middleMCP.x - wrist.x, dy: middleMCP.y - wrist.y)
        )
    }

    private static func fingerState(
        _ finger: FingerJoints,
        in geometry: HandGeometry
    ) -> FingerState {
        guard geometry.points[finger.base] != nil,
              let middle = geometry.points[finger.middle] else { return .unknown }
        let middleReach = geometry.reach(middle)
        let end: (point: CGPoint, margin: CGFloat)
        if let tip = geometry.points[finger.tip] {
            end = (tip, tipExtensionMargin)
        } else if let distal = geometry.points[finger.distal] {
            end = (distal, distalExtensionMargin)
        } else {
            // 주먹에서는 손끝과 DIP가 손바닥·엄지에 가려 신뢰도가 낮아집니다.
            // 펴진 손가락의 끝은 잘 보이므로, MCP·PIP만 보이면 접힌 것으로 판단합니다.
            return .curled
        }

        let endReach = geometry.reach(end.point)
        if endReach <= middleReach || endReach < curledReachLimit { return .curled }
        if endReach - middleReach >= end.margin { return .extended }
        return .unknown
    }

    /// 엄지는 주먹에서 손가락 위나 옆에 놓일 수 있어 방향만으로는 접힘을 판단하기 어렵습니다.
    /// 손끝이 검지 MCP에서 얼마나 떨어졌는지로 손바닥 밖으로 펴졌는지를 봅니다.
    private static func thumbState(in geometry: HandGeometry) -> FingerState {
        guard let tip = geometry.points[.thumbTip] ?? geometry.points[.thumbIP],
              let indexMCP = geometry.points[.indexMCP] else { return .unknown }
        let spread = distance(tip, indexMCP) / geometry.palmLength
        if spread >= thumbExtendedReach { return .extended }
        if spread <= thumbTuckedReach { return .curled }
        return .unknown
    }

    /// 일부 관절이 판단 불가여도 나머지가 충분히 확실하면 포즈를 결정합니다.
    private static func pose(fingers: [FingerState], thumb: FingerState) -> HandPose? {
        let extended = fingers.filter { $0 == .extended }.count
        let curled = fingers.filter { $0 == .curled }.count

        switch (extended, curled) {
        case (4, _) where thumb != .curled:
            return .openHand
        case (0, 3...) where thumb != .extended:
            return .fist
        case (1, 2...) where thumb != .extended:
            return .oneFinger
        case (3, 1) where thumb != .extended, (2, 2) where thumb == .extended:
            return .threeFingers
        default:
            return nil
        }
    }

    private static func distance(_ firstPoint: CGPoint, _ secondPoint: CGPoint) -> CGFloat {
        hypot(firstPoint.x - secondPoint.x, firstPoint.y - secondPoint.y)
    }
}
