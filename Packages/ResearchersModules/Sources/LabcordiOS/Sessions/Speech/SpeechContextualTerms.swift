import Foundation

/// 저장된 용어는 보존하고 음성 인식에 전달할 단순 괄호 별칭·방식만 분리합니다.
nonisolated enum SpeechContextualTerms {
    static func prepare(_ terms: [String]) -> [String] {
        var seen = Set<String>()
        return terms.flatMap(split).map(removingCalculationDirective)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private static func removingCalculationDirective(_ term: String) -> String {
        let words = term.split(separator: " ")
        guard words.count >= 3, words.count <= 5,
              let first = words.first,
              ["compute", "calculate", "determine"].contains(first.lowercased()),
              !["if", "whether", "how", "which", "the", "a", "an"]
                .contains(words[1].lowercased()),
              !words.dropFirst().contains(where: {
                  ["is", "are", "was", "were", "has", "have", "will", "should"]
                    .contains($0.lowercased())
              }),
              words.dropFirst().allSatisfy({ word in
                  word.allSatisfy { $0.isLetter || $0 == "-" }
              }) else { return term }
        return words.dropFirst().joined(separator: " ")
    }

    private static func split(_ value: String) -> [String] {
        let term = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let pairs: [Character: Character] = [")": "(", "）": "（"]
        guard let last = term.last, let opening = pairs[last],
              let start = term.firstIndex(of: opening) else { return [term] }
        let base = String(term[..<start]).trimmingCharacters(in: .whitespaces)
        let inner = String(term[term.index(after: start)..<term.index(before: term.endIndex)])
            .trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty, !inner.isEmpty,
              !base.contains(where: { "()（）".contains($0) }),
              !inner.contains(where: { "()（）".contains($0) }) else { return [term] }
        if inner.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) }) {
            return [base]
        }
        // 농도·대안·복합 화학식은 별칭으로 단정하지 않습니다.
        guard base.unicodeScalars.contains(where: { (0xAC00...0xD7A3).contains($0.value) }),
              inner.first?.isLetter == true,
              inner.range(of: "^[\\p{L}\\p{N}]+(?:[ -][\\p{L}\\p{N}]+)*$",
                          options: .regularExpression) != nil,
              inner.range(of: "(?i)\\b(?:or|and|equivalent|optional)\\b|선택|제외|포함",
                          options: .regularExpression) == nil else { return [term] }
        let asciiLetters = inner.unicodeScalars.filter {
            (65...90).contains($0.value) || (97...122).contains($0.value)
        }
        if asciiLetters.count <= 2, asciiLetters.count == inner.unicodeScalars.count {
            return [term]
        }
        return [base, inner]
    }
}
