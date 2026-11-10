import Foundation

// swiftlint:disable:next type_body_length
nonisolated enum EnglishKoreanPhonetic {
    private static let vowels: Set<Character> = [
        "ㅏ", "ㅐ", "ㅑ", "ㅒ", "ㅓ", "ㅔ", "ㅕ", "ㅖ", "ㅗ", "ㅘ", "ㅙ", "ㅚ",
        "ㅛ", "ㅜ", "ㅝ", "ㅞ", "ㅟ", "ㅠ", "ㅡ", "ㅢ", "ㅣ"
    ]

    private static let choseongIndex: [Character: Int] = Dictionary(
        uniqueKeysWithValues: Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ").enumerated().map { ($1, $0) }
    )
    private static let jungseongIndex: [Character: Int] = Dictionary(
        uniqueKeysWithValues: Array("ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ").enumerated().map { ($1, $0) }
    )
    private static let jongseongIndex: [Character: Int] = Dictionary(
        uniqueKeysWithValues: Array(" ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ").enumerated().map { ($1, $0) }
    )

    private static let doubleConsonants: Set<String> = [
        "bb", "cc", "dd", "ff", "gg", "ll", "mm", "nn", "pp", "rr", "ss", "tt"
    ]

    static let letterNames: [Character: String] = [
        "a": "에이", "b": "비", "c": "씨", "d": "디", "e": "이",
        "f": "에프", "g": "지", "h": "에이치", "i": "아이", "j": "제이",
        "k": "케이", "l": "엘", "m": "엠", "n": "엔", "o": "오",
        "p": "피", "q": "큐", "r": "알", "s": "에스", "t": "티",
        "u": "유", "v": "브이", "w": "더블유", "x": "엑스", "y": "와이",
        "z": "제트"
    ]

    private static let patterns: [(String, String)] = [
        ("able", "ㅔㅣㅂㅡㄹ"),
        ("tion", "ㅅㅕㄴ"),
        ("sion", "ㅅㅕㄴ"),
        ("ture", "ㅊㅓ"),
        ("sure", "ㅅㅕ"),
        ("cial", "ㅅㅕㄹ"),
        ("tial", "ㅅㅕㄹ"),
        ("ough", "ㅗ"),
        ("eigh", "ㅣ"),
        ("augh", "ㅗ"),
        ("aigh", "ㅣ"),
        ("que", "ㅋㅞ"),
        ("qui", "ㅋㅟ"),
        ("dge", "ㅈㅣ"),
        ("tch", "ㅊ"),
        ("whi", "ㅎㅘ"),
        ("wha", "ㅇㅘ"),
        ("you", "ㅠ"),
        ("igh", "ㅣ"),
        ("ate", "ㅔㅣㅌㅡ"),
        ("ite", "ㅏㅣㅌㅡ"),
        ("ide", "ㅏㅣㄷㅡ"),
        ("ase", "ㅔㅣㅅㅡ"),
        ("ose", "ㅗㅅㅡ"),
        ("one", "ㅗㄴ"),
        ("ine", "ㅣㄴ"),
        ("ene", "ㅔㄴ"),
        ("ane", "ㅔㅣㄴ"),
        ("ium", "ㅠㅁ"),
        ("ous", "ㅓㅅㅡ"),
        ("ble", "ㅂㅡㄹ")
    ]

    static func transliterate(_ text: String) -> String? {
        var output = ""
        var changed = false
        var index = text.startIndex
        while index < text.endIndex {
            let scalar = text[index]
            if scalar.isASCII, scalar.isLetter {
                let end = text[index...]
                    .firstIndex { !$0.isASCII || !$0.isLetter } ?? text.endIndex
                let word = String(text[index..<end])
                if let korean = transliterateWord(word) {
                    output += korean
                    changed = true
                } else {
                    output += word
                }
                index = end
            } else {
                output.append(scalar)
                index = text.index(after: index)
            }
        }
        return changed ? output : nil
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private static func transliterateWord(_ raw: String) -> String? {
        var word = raw.lowercased()
        guard word.contains(where: { $0.isASCII && $0.isLetter }) else { return nil }
        word = word.filter { $0.isASCII && ($0.isLetter || $0 == "-") }
        guard !word.isEmpty else { return nil }
        if raw.count <= 3, raw.allSatisfy({ $0.isASCII && $0.isLetter }),
           raw == raw.uppercased() {
            return raw.lowercased().compactMap { letterNames[$0] }.joined()
        }

        if raw.contains(where: { $0.isLowercase }),
           raw.dropFirst().contains(where: { $0.isUppercase }) { return nil }

        var longVowelPosition: String.Index?
        if word.count >= 3, word.hasSuffix("e"),
           let lastConsonant = word.dropLast().last, !isVowelChar(lastConsonant),
           word.dropLast().dropLast().contains(where: { isVowelChar($0) }),
           let vowelIndex = word.dropLast().dropLast().lastIndex(where: { isVowelChar($0) }) {
            longVowelPosition = vowelIndex
        }
        if word.hasSuffix("e"), word.count > 1,
           !patterns.contains(where: { word.hasSuffix($0.0) }) {
            word.removeLast()
        }

        var jamo: [Character] = []
        // swiftlint:disable:next identifier_name
        var i = word.startIndex
        while i < word.endIndex {
            let rest = String(word[i...])
            if let hit = patterns.first(where: { rest.hasPrefix($0.0) }) {
                jamo += hit.1
                i = word.index(i, offsetBy: hit.0.count)
                continue
            }
            let pair = rest.count >= 2 ? String(rest.prefix(2)) : ""
            if pair.count == 2 {
                if let mapped = mapPair(pair) {
                    jamo += mapped
                    i = word.index(i, offsetBy: 2)
                    continue
                }
                if doubleConsonants.contains(pair),
                   let mapped = mapSingle(pair.first!, isLongVowel: false) {
                    jamo.append(mapped)
                    i = word.index(i, offsetBy: 2)
                    continue
                }
            }
            if word[i...].hasPrefix("mb"),
               word.index(i, offsetBy: 2) == word.endIndex {
                jamo.append("ㅁ")
                i = word.index(i, offsetBy: 2)
                continue
            }

            if i == word.index(before: word.endIndex),
               word.hasSuffix("l"), word.count > 2 {
                let prev = word.index(i, offsetBy: -1)
                if let prevChar = mapSingle(word[prev], isLongVowel: false),
                   !vowels.contains(prevChar) {
                    jamo += "ㅡㄹ"
                    i = word.index(after: i)
                    continue
                }
            }
            if let single = mapSingle(word[i], isLongVowel: i == longVowelPosition) {
                jamo.append(single)
            }
            i = word.index(after: i)
        }
        return compose(jamo)
    }

    // swiftlint:disable:next cyclomatic_complexity
    private static func mapPair(_ pair: String) -> String? {
        switch pair {
        case "ai", "ay": return "ㅐ"
        case "ea", "ee": return "ㅣ"
        case "ei", "ey": return "ㅔ"
        case "ie": return "ㅣ"
        case "oa": return "ㅗ"
        case "oe", "oi": return "ㅚ"
        case "oo": return "ㅜ"
        case "ou", "ow": return "ㅏㅜ"
        case "au", "aw": return "ㅗ"
        case "ui": return "ㅟ"
        case "ue": return "ㅜ"
        case "ew": return "ㅠ"
        case "ia": return "ㅣㅏ"
        case "io": return "ㅣㅗ"
        case "ya": return "ㅑ"
        case "ye": return "ㅖ"
        case "yi": return "ㅣ"
        case "yo": return "ㅛ"
        case "yu": return "ㅠ"
        case "th", "sh", "wh": return "ㅅ"
        case "ch": return "ㅊ"
        case "ph": return "ㅍ"
        case "ck": return "ㅋ"
        case "ng": return "ㅇ"
        case "wa": return "ㅘ"
        case "we": return "ㅞ"
        case "wi": return "ㅟ"
        case "wo": return "ㅝ"
        case "ci": return "ㅅㅣ"
        case "ce": return "ㅅㅔ"
        case "gi": return "ㅈㅣ"
        case "ge": return "ㅈㅔ"
        case "gy": return "ㅈㅣ"
        case "nk": return "ㄴㅋ"
        case "wr": return "ㄹ"
        case "kn", "gn", "ps": return "ㄴ"
        case "dg": return "ㅈ"
        case "rh": return "ㄹ"
        default: return nil
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    private static func mapSingle(_ char: Character, isLongVowel: Bool) -> Character? {
        switch char {
        case "a": return isLongVowel ? "ㅐ" : "ㅏ"
        case "e": return isLongVowel ? "ㅣ" : "ㅔ"
        case "i": return "ㅣ"
        case "o": return "ㅗ"
        case "u": return isLongVowel ? "ㅠ" : "ㅜ"
        case "y": return "ㅣ"
        case "b": return "ㅂ"
        case "c": return "ㅋ"
        case "d": return "ㄷ"
        case "f": return "ㅍ"
        case "g": return "ㄱ"
        case "h": return "ㅎ"
        case "j": return "ㅈ"
        case "k": return "ㅋ"
        case "l": return "ㄹ"
        case "m": return "ㅁ"
        case "n": return "ㄴ"
        case "p": return "ㅍ"
        case "q": return "ㅋ"
        case "r": return "ㄹ"
        case "s": return "ㅅ"
        case "t": return "ㅌ"
        case "v": return "ㅂ"
        case "w": return "ㅇ"
        case "x": return "ㅋ"
        case "z": return "ㅈ"
        default: return nil
        }
    }

    private static func finalJamo(_ char: Character) -> Character {
        switch char {
        case "ㅋ": return "ㄱ"
        case "ㅌ": return "ㅅ"
        case "ㅍ": return "ㅂ"
        default: return char
        }
    }

    private static func isVowelChar(_ char: Character) -> Bool {
        "aeiouy".contains(char)
    }

    // swiftlint:disable identifier_name
    private static func compose(_ jamo: [Character]) -> String {
        var choseong: Character?
        var jungseong: Character?
        var jongseong: Character?
        var output = ""

        func flush() {
            guard let c = choseong else { return }
            let v = jungseong ?? "ㅡ"
            let j = jongseong
            guard let ci = choseongIndex[c], let vi = jungseongIndex[v] else {
                output.append(c)
                output.append(v)
                if let j { output.append(j) }
                choseong = nil
                jungseong = nil
                jongseong = nil
                return
            }
            let ji = j.flatMap { jongseongIndex[$0] } ?? 0
            let code = 0xAC00 + (ci * 21 + vi) * 28 + ji
            output.unicodeScalars.append(UnicodeScalar(code)!)
            choseong = nil
            jungseong = nil
            jongseong = nil
        }

        for (index, char) in jamo.enumerated() {
            let nextIsVowel = index + 1 < jamo.count && vowels.contains(jamo[index + 1])
            if vowels.contains(char) {
                if jungseong != nil {
                    flush()
                }
                if choseong == nil { choseong = "ㅇ" }
                jungseong = char
            } else if let jong = jongseongIndex[char], jong > 0 {
                if jungseong != nil, jongseong == nil, char == "ㅇ" || !nextIsVowel {
                    jongseong = finalJamo(char)
                } else {
                    flush()
                    choseong = char
                }
            }
        }
        flush()
        return output
    }
    // swiftlint:enable identifier_name
}
