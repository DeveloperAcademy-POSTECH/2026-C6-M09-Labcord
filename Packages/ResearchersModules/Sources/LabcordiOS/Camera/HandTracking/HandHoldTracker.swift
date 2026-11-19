import Foundation

nonisolated enum HandPose: Equatable {
    case openHand
    case fist
    case oneFinger
    case threeFingers
}

nonisolated struct HandHoldTracker {
    private let holdDuration: TimeInterval
    private let releaseGrace: TimeInterval
    private let switchDelay: TimeInterval
    private var candidate: HandPose?
    private var candidateStart: TimeInterval?
    private var challenger: HandPose?
    private var challengerStart: TimeInterval?
    private var lastDetection: TimeInterval?
    private var didEmit = false

    init(
        holdDuration: TimeInterval = 1,
        releaseGrace: TimeInterval = 0.45,
        switchDelay: TimeInterval = 0.25
    ) {
        self.holdDuration = holdDuration
        self.releaseGrace = releaseGrace
        self.switchDelay = switchDelay
    }

    mutating func reset() {
        candidate = nil
        candidateStart = nil
        challenger = nil
        challengerStart = nil
        lastDetection = nil
        didEmit = false
    }

    mutating func update(_ pose: HandPose?, at time: TimeInterval) -> HandPose? {
        guard let pose else {
            if let lastDetection, time - lastDetection >= releaseGrace { reset() }
            return nil
        }

        let isStale = lastDetection.map { time - $0 >= releaseGrace } ?? true
        lastDetection = time
        if isStale || candidate == nil {
            start(pose, at: time)
        } else if pose == candidate {
            challenger = nil
            challengerStart = nil
        } else if pose == challenger, let challengerStart {
            guard time - challengerStart >= switchDelay else { return nil }
            start(pose, at: challengerStart)
        } else {
            challenger = pose
            challengerStart = time
            return nil
        }

        guard !didEmit, let candidateStart, time - candidateStart >= holdDuration else {
            return nil
        }
        didEmit = true
        return candidate
    }

    private mutating func start(_ pose: HandPose, at time: TimeInterval) {
        candidate = pose
        candidateStart = time
        challenger = nil
        challengerStart = nil
        didEmit = false
    }
}
