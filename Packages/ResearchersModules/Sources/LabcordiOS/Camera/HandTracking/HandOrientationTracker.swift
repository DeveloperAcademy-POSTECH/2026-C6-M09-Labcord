import CoreGraphics
import ImageIO

nonisolated struct HandOrientationTracker {

    private static let initialQuarterTurns = 1

    private static let switchAngle: CGFloat = .pi / 3
    private static let searchAfterMissedFrames = 6

    private(set) var quarterTurns = initialQuarterTurns
    private var missedFrames = 0

    var orientation: CGImagePropertyOrientation {
        switch quarterTurns {
        case 1: .left
        case 2: .down
        case 3: .right
        default: .up
        }
    }

    mutating func reset() {
        quarterTurns = Self.initialQuarterTurns
        missedFrames = 0
    }

    mutating func update(pointingDirection: CGVector?, isHandDetected: Bool) {
        if let pointingDirection {
            missedFrames = 0
            var offset = atan2(pointingDirection.dy, pointingDirection.dx) - .pi / 2
            if offset > .pi { offset -= 2 * .pi }
            if offset <= -.pi { offset += 2 * .pi }
            guard abs(offset) >= Self.switchAngle else { return }
            let turns = Int((-offset / (.pi / 2)).rounded())
            quarterTurns = ((quarterTurns + turns) % 4 + 4) % 4
            return
        }
        guard !isHandDetected else { return }
        missedFrames += 1
        guard missedFrames >= Self.searchAfterMissedFrames else { return }
        missedFrames = 0
        quarterTurns = (quarterTurns + 1) % 4
    }

    static func rawPoint(_ point: CGPoint, quarterTurns: Int) -> CGPoint {
        switch quarterTurns {
        case 1: CGPoint(x: point.y, y: 1 - point.x)
        case 2: CGPoint(x: 1 - point.x, y: 1 - point.y)
        case 3: CGPoint(x: 1 - point.y, y: point.x)
        default: point
        }
    }
}
