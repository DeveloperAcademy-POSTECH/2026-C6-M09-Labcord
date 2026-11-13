import Foundation

public enum ExperimentTitle {
    public static func numbered(_ title: String, number: Int) -> String {
        "\(title) (\(number))"
    }

    public static func availableNumber(
        for title: String, startingAt start: Int, existing: Set<String>
    ) -> Int {
        var number = start
        while existing.contains(numbered(title, number: number)) {
            number += 1
        }
        return number
    }

    public static func unique(_ title: String, existing: Set<String>) -> String {
        guard existing.contains(title) else { return title }
        var base = title
        if let range = title.range(of: #" \([0-9]+\)$"#, options: .regularExpression) {
            let candidate = String(title[..<range.lowerBound])
            if existing.contains(candidate) || (title.count == 60 && existing.contains {
                $0.count == 60 && $0.hasPrefix(candidate)
            }) {
                base = candidate
            }
        }
        var number = 2
        while true {
            let suffix = " (\(number))"
            let shortened = String(base.prefix(max(0, 60 - suffix.count)))
            let candidate = numbered(shortened, number: number)
            if !existing.contains(candidate) { return candidate }
            number += 1
        }
    }
}
