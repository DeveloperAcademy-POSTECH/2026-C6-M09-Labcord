import Foundation

public struct TimerDurationComponents: Equatable, Sendable {
    public let value: String
    public let unit: String

    public var text: String { value + unit }
}

public struct TimerDurationFormatStyle: FormatStyle, Sendable {
    public init() { }

    public func format(_ value: Duration) -> String {
        components(value).text
    }

    public func components(_ duration: Duration) -> TimerDurationComponents {
        let total = duration.components.seconds
        let magnitude = total.magnitude
        let hours = magnitude / 3_600
        let minutes = magnitude % 3_600 / 60
        let seconds = magnitude % 60
        let sign = total < 0 ? "-" : ""
        let parts: [(UInt64, String)] = [
            (hours, "시간"), (minutes, "분"), (seconds, "초")
        ].filter { $0.0 > 0 }
        let last = parts.last ?? (0, "초")
        let prefix = parts.dropLast().map { "\($0.0)\($0.1)" }
        let value = (prefix + [String(last.0)]).joined(separator: " ")
        return TimerDurationComponents(value: sign + value, unit: last.1)
    }
}

public struct TimerClockFormatStyle: FormatStyle, Sendable {
    public let includesHours: Bool

    public init(includesHours: Bool = false) {
        self.includesHours = includesHours
    }

    public func format(_ duration: Duration) -> String {
        let wholeSeconds = Duration.seconds(duration.components.seconds)
        if includesHours {
            return wholeSeconds.formatted(
                .time(pattern: .hourMinuteSecond(padHourToLength: 2))
            )
        }
        return wholeSeconds.formatted(.time(pattern: .minuteSecond(padMinuteToLength: 2)))
    }
}

public extension FormatStyle where Self == TimerDurationFormatStyle {
    static var labcordDuration: Self { Self() }
}

public extension FormatStyle where Self == TimerClockFormatStyle {
    static func labcordClock(includesHours: Bool = false) -> Self {
        Self(includesHours: includesHours)
    }
}
