import Foundation
import FoundationModels

nonisolated public enum SpeechPhoneticTranslator {
    private static let batchSize = 25

    public static func prewarm(terms: [String]) async {
        var seen = Set<String>()
        let misses = SpeechVocabulary.terms(from: terms)
            .filter {
                SpeechVocabulary.containsASCIILettersWithoutHangul($0)
                    && seen.insert($0.lowercased()).inserted
            }
            .filter { TermStringCache.readings.value(for: $0) == nil }
        guard !misses.isEmpty else { return }
        guard case .available = SystemLanguageModel.default.availability else {
            SpeechDebugLog.write(
                "phonetic prewarm skipped: \(SystemLanguageModel.default.availability)"
            )
            return
        }
        SpeechDebugLog.write("phonetic prewarm: \(misses.count) terms")
        for start in stride(from: 0, to: misses.count, by: batchSize) {
            let end = min(start + batchSize, misses.count)
            let readings = await transliterateBatch(Array(misses[start..<end]))
            if !readings.isEmpty { TermStringCache.readings.store(readings) }
        }
    }

    static func cachedReading(for term: String) -> String? {
        TermStringCache.readings.value(for: term)
    }

    private static func transliterateBatch(_ terms: [String]) async -> [String: String] {
        let stringSchema = DynamicGenerationSchema(type: String.self)
        let properties = terms.map { term in
            DynamicGenerationSchema.Property(
                name: term,
                description: "How a Korean speaker pronounces \(term), in Hangul",
                schema: stringSchema
            )
        }
        let root = DynamicGenerationSchema(
            name: "KoreanReadings",
            description: "Korean phonetic readings of English terms",
            properties: properties
        )
        guard let schema = try? GenerationSchema(root: root, dependencies: []) else {
            return [:]
        }
        let session = LanguageModelSession(instructions: """
            You write how Korean lab researchers pronounce English terms, in Hangul.
            Transliterate the sound (외래어 표기). Never translate the meaning.
            Spell acronyms and formulas letter by letter.
            Examples:
            - protocol → 프로토콜
            - sample → 샘플
            - RPM → 알피엠
            """)
        let list = terms.map { "- \($0)" }.joined(separator: "\n")
        do {
            let response = try await session.respond(
                to: "Terms:\n\(list)",
                schema: schema,
                options: GenerationOptions(samplingMode: .greedy)
            )
            return readings(from: response.content, terms: terms)
        } catch {
            return [:]
        }
    }

    private static func readings(
        from content: GeneratedContent, terms: [String]
    ) -> [String: String] {
        guard case let .structure(properties, _) = content.kind else { return [:] }
        var result: [String: String] = [:]
        for term in terms {
            guard let value = properties[term],
                  let reading = try? value.value(String.self),
                  reading.contains(where: { character in
                      character.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) }
                  }) else { continue }
            result[term] = reading
        }
        return result
    }
}
