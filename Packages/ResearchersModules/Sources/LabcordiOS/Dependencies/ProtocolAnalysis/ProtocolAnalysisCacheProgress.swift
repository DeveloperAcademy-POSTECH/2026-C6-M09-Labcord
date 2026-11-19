nonisolated enum ProtocolAnalysisCacheProgress {
    static func samples(count: Int) -> [Double] {
        var distance = 0.0
        var speed = Double.random(in: 0.2...0.45)
        var distances: [Double] = []
        distances.reserveCapacity(count)

        while distances.count < count {
            let isAccelerating = speed < 1
            let length = Int.random(in: isAccelerating ? 5...11 : 17...28)
            let transitionTicks = isAccelerating ? 2 : 3
            let target = Double.random(in: isAccelerating ? 1.8...3.5 : 0.2...0.45)
            for tick in 1...min(length, count - distances.count) {
                let fraction = Double(min(tick, transitionTicks)) / Double(transitionTicks)
                distance += speed + (target - speed) * fraction
                distances.append(distance)
            }
            speed = target
        }

        // Reserve the 100% display for the last tick.
        return distances.dropLast().map { 0.994 * $0 / distance } + [1]
    }
}
