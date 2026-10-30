public enum TimerDurationFormatter {
    public static func string(from totalSeconds: Int) -> String {
        let totalSeconds = max(0, totalSeconds)
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        var parts: [String] = []

        if hours > 0 { parts.append("\(hours)시간") }
        if minutes > 0 { parts.append("\(minutes)분") }
        if seconds > 0 || parts.isEmpty { parts.append("\(seconds)초") }

        return parts.joined(separator: " ")
    }
}
