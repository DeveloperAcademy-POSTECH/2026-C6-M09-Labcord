import Foundation

nonisolated enum HandPose: Equatable {
    case openHand
    case fist
    case oneFinger
}

nonisolated struct HandHoldTracker {
    private let holdDuration: TimeInterval
    private let releaseGrace: TimeInterval
    private var candidate: HandPose?
    private var candidateStart: TimeInterval?
    private var lastDetection: TimeInterval?
    private var didEmit = false

    init(holdDuration: TimeInterval = 1, releaseGrace: TimeInterval = 0.45) {
        self.holdDuration = holdDuration
        self.releaseGrace = releaseGrace
    }

    mutating func reset() {
        candidate = nil
        candidateStart = nil
        lastDetection = nil
        didEmit = false
    }

    mutating func update(_ pose: HandPose?, at time: TimeInterval) -> HandPose? {
        guard let pose else {
            if let lastDetection, time - lastDetection >= releaseGrace { reset() }
            return nil
        }

        if candidate != pose || lastDetection.map({ time - $0 >= releaseGrace }) ?? true {
            candidate = pose
            candidateStart = time
            didEmit = false
        }
        lastDetection = time

        guard !didEmit, time - (candidateStart ?? time) >= holdDuration else { return nil }
        didEmit = true
        return pose
    }
}
