public enum TimerDurationFormatter {
    public struct Components: Equatable, Sendable {
        public let value: String
        public let unit: String

        public var text: String { value + unit }
    }

    public static func string(from totalSeconds: Int) -> String {
        components(magnitude: UInt64(max(0, totalSeconds))).text
    }

    public static func components(magnitude totalSeconds: UInt64) -> Components {
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        let parts: [(UInt64, String)] = [
            (hours, "시간"), (minutes, "분"), (seconds, "초")
        ].filter { $0.0 > 0 }
        let last = parts.last ?? (0, "초")
        let prefix = parts.dropLast().map { "\($0.0)\($0.1)" }
        return Components(
            value: (prefix + [String(last.0)]).joined(separator: " "),
            unit: last.1
        )
    }
}
