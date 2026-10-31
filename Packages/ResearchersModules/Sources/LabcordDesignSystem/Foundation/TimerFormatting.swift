import Foundation
import LabcordShared

public struct TimerDurationComponents: Equatable, Sendable {
    public let value: String
    public let unit: String

    public var text: String { value + unit }
}

public struct TimerDurationFormatStyle: FormatStyle, Sendable {
    public init() { }

    public func format(_ value: Duration) -> String {
        formattedParts(for: value).text
    }

    public func formattedParts(for duration: Duration) -> TimerDurationComponents {
        let total = duration.components.seconds
        let formatted = TimerDurationFormatter.components(magnitude: total.magnitude)
        let sign = total < 0 ? "-" : ""
        return TimerDurationComponents(value: sign + formatted.value, unit: formatted.unit)
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
