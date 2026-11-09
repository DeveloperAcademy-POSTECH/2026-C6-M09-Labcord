import Foundation

nonisolated struct SpeechUnitNormalizer {
    private static let prefixes: [(String, String)] = [
        ("펨토", "f"), ("피코", "p"), ("나노", "n"), ("마이크로", "µ"), ("밀리", "m"),
        ("센티", "c"), ("데시", "d"), ("킬로", "k"), ("메가", "M"), ("기가", "G"), ("테라", "T")
    ]
    private static let bases: [(String, String)] = [
        ("리터", "L"), ("그램", "g"), ("몰", "mol"), ("몰라", "M"),
        ("미터", "m"), ("초", "s"), ("파스칼", "Pa"), ("헤르츠", "Hz"),
        ("달톤", "Da"), ("볼트", "V"), ("암페어", "A"), ("와트", "W"),
        ("줄", "J"), ("뉴턴", "N"), ("옴", "Ω"), ("지멘스", "S"),
        ("패럿", "F"), ("헨리", "H"), ("유닛", "U"), ("인터내셔널유닛", "IU")
    ]
    private static let catalog: [(String, String)] = {
        var values = prefixes.flatMap { prefix in
            bases.map { (prefix.0 + $0.0, prefix.1 + $0.1) }
        } + bases
        values += prefixes.map { ($0.0 + "몰", $0.1 + "M") }
        values += [
            ("밀리그램퍼밀리리터", "mg/mL"), ("마이크로그램퍼밀리리터", "µg/mL"),
            ("나노그램퍼밀리리터", "ng/mL"), ("그램퍼리터", "g/L"),
            ("몰퍼리터", "mol/L"), ("밀리몰퍼리터", "mmol/L"),
            ("퍼센트", "%"), ("도씨", "°C"), ("섭씨", "°C"), ("화씨", "°F"),
            ("켈빈", "K"), ("몰", "M"), ("알피엠", "rpm"), ("피피엠", "ppm"), ("피피비", "ppb"),
            ("시간", "h"), ("분", "min"), ("시", "h"), ("유닛", "U"),
            ("인터내셔널유닛", "IU"), ("염기쌍", "bp"), ("킬로베이스", "kb"),
            ("뉴클레오타이드", "nt"), ("바", "bar"), ("기압", "atm"),
            ("피에스아이", "psi"), ("밀리미터수은주", "mmHg"),
            ("센티미터물기둥", "cmH2O"), ("뉴턴", "N"), ("제곱미터", "m²"),
            ("세제곱미터", "m³"), ("곱하기지", "×g"), ("배지", "×g"),
            ("볼륨퍼볼륨", "v/v"), ("웨이트퍼볼륨", "w/v"), ("웨이트퍼웨이트", "w/w"),
            ("피에이치", "pH"), ("오디", "OD"), ("상대습도", "RH")
        ]
        return values.sorted { $0.0.count > $1.0.count }
    }()
    private static let minuteContext = try? NSRegularExpression(
        pattern: #"^[ \t]*(?:동안|후|뒤|간)(?=$|[ \t.,!?를을에의])"#
    )

    private let symbols: [String: String]
    private let regex: NSRegularExpression?
    var hints: [String] { symbols.keys.sorted() }

    init(units: [String]) {
        var matches: [String: Set<String>] = [:]
        for original in units {
            let unit = original.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: #"^[0-9.,]+\s*"#, with: "", options: .regularExpression)
            let key = Self.unitKey(unit)
            guard !key.isEmpty else { continue }
            for (reading, symbol) in Self.catalog where Self.unitKey(symbol) == key {
                matches[reading, default: []].insert(unit)
            }

            let components = key.split(separator: "/", omittingEmptySubsequences: false)
            if components.count == 2 {
                let left = Self.catalog.filter { Self.unitKey($0.1) == components[0] }
                let right = Self.catalog.filter { Self.unitKey($0.1) == components[1] }
                for numerator in left {
                    for denominator in right {
                        matches[numerator.0 + "퍼" + denominator.0, default: []].insert(unit)
                    }
                }
            }
        }
        symbols = matches.compactMapValues { $0.count == 1 ? $0.first : nil }
        let alternatives = symbols.keys.sorted { $0.count > $1.count }
            .map { $0.map { NSRegularExpression.escapedPattern(for: String($0)) }
                .joined(separator: #"[ \t]*"#) }.joined(separator: "|")
        if alternatives.isEmpty {
            regex = nil
        } else {
            regex = try? NSRegularExpression(
                pattern: #"(?<![0-9A-Za-z가-힣])([+-]?[0-9]+(?:[.,][0-9]+)?)[ \t]*("#
                    + alternatives
                    + #")(?=(?:을|를|이|가|은|는|의|에|로|으로|와|과|씩)?(?:[^가-힣A-Za-z]|$))"#
            )
        }
    }

    private static func unitKey(_ unit: String) -> String {
        unit.replacingOccurrences(of: "μ", with: "µ")
            .replacingOccurrences(
                of: #"(?<![A-Za-z])u(?=[A-Za-z])"#, with: "µ", options: .regularExpression
            )
            .replacingOccurrences(of: #"(?<![A-Za-z])([fpnµmcdhkMGT]?)(l)(?![A-Za-z])"#,
                                  with: "$1L", options: .regularExpression)
            .replacingOccurrences(of: "℃", with: "°C")
            .replacingOccurrences(of: "℉", with: "°F")
            .replacingOccurrences(of: " ", with: "")
    }

    func normalize(_ text: String) -> String {
        guard let regex else { return text }
        var output = text
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches.reversed() {
            guard let range = Range(match.range, in: output),
                  let numberRange = Range(match.range(at: 1), in: output),
                  let unitRange = Range(match.range(at: 2), in: output),
                  let symbol = symbols[output[unitRange].filter({ !$0.isWhitespace })] else {
                continue
            }
            let reading = output[unitRange].filter { !$0.isWhitespace }
            if reading == "분" {
                let suffix = String(output[range.upperBound...])
                let suffixRange = NSRange(suffix.startIndex..., in: suffix)
                guard Self.minuteContext?.firstMatch(in: suffix, range: suffixRange) != nil else {
                    continue
                }
            }
            output.replaceSubrange(range, with: String(output[numberRange]) + " " + symbol)
        }
        return output
    }
}
