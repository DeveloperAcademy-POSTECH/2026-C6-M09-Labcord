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

        if hours > 0 {
            if minutes == 0 && seconds == 0 {
                return Components(value: String(hours), unit: "시간")
            }
            if seconds == 0 {
                return Components(
                    value: "\(twoDigits(hours)):\(twoDigits(minutes))",
                    unit: "시간"
                )
            }
            return Components(
                value: "\(twoDigits(hours)):\(twoDigits(minutes)):\(twoDigits(seconds))",
                unit: "시간"
            )
        }

        if minutes > 0 {
            if seconds == 0 {
                return Components(value: String(minutes), unit: "분")
            }
            return Components(value: "\(twoDigits(minutes)):\(twoDigits(seconds))", unit: "분")
        }

        return Components(value: String(seconds), unit: "초")
    }

    private static func twoDigits(_ value: UInt64) -> String {
        value < 10 ? "0\(value)" : String(value)
    }
}
