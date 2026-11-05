import Foundation

public enum ExperimentResultDateFormatter {
    private static let fullDateFormatter = makeFormatter("yyyy년 MM월 dd일")
    private static let timeFormatter = makeFormatter("HH:mm:ss")
    private static let monthDayFormatter = makeFormatter("MM월 dd일")

    public static func date(_ date: Date) -> String {
        fullDateFormatter.string(from: date)
    }

    public static func time(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    public static func range(startedAt: Date?, endedAt: [Date]) -> String? {
        guard let startedAt, let endedAt = endedAt.last else { return nil }

        return "\(date(startedAt)) ~ \(monthDayFormatter.string(from: endedAt))"
    }

    private static func makeFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = format
        return formatter
    }
}
