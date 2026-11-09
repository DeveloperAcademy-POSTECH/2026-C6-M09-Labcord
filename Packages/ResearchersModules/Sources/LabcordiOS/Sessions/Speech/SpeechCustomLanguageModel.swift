import CryptoKit
import Foundation
import Speech

nonisolated public enum SpeechCustomLanguageModel {
    private static let version = "2.0"
    private static let maxTerms = 150

    private static let carrierTemplates: [(body: String, weight: Int)] = [
        ("<term>", 6), ("<term> 넣고", 2), ("<term> 넣어", 2), ("<term> 추가", 2),
        ("<term> 용액", 2), ("<term> 농도", 1), ("<term> 확인", 1)
    ]

    public static func hint(
        for terms: [String], locale: Locale
    ) async -> SpeechLanguageModelHint? {
        let phrases = spokenForms(for: terms)
        guard !phrases.isEmpty else { return nil }
        let hint = makeHint(keyParts: [version] + phrases)
        let prepared = await prepare(
            phrases: phrases, locale: locale, directory: hint.directory,
            configuration: hint.configuration
        )
        return prepared ? hint.configuration : nil
    }

    private static func spokenForms(for terms: [String]) -> [String] {
        var seen = Set<String>()
        return terms
            .compactMap {
                SpeechVocabulary.readings(
                    for: $0, modelReading: SpeechPhoneticTranslator.cachedReading(for: $0)
                ).first
            }
            .filter { seen.insert($0).inserted }
            .prefix(maxTerms)
            .map { $0 }
    }

    private static func prepare(
        phrases: [String], locale: Locale, directory: URL,
        configuration: SpeechLanguageModelHint
    ) async -> Bool {
        let readyMarker = directory.appendingPathComponent("ready")
        guard !FileManager.default.fileExists(atPath: readyMarker.path) else {
            return true
        }
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true
            )
            let data = SFCustomLanguageModelData(
                locale: locale,
                identifier: "com.baserize.labcord.speechlm",
                version: version
            )
            let generator = SFCustomLanguageModelData.TemplatePhraseCountGenerator()
            generator.define(className: "term", values: phrases)
            for template in carrierTemplates {
                generator.insert(template: template.body, count: template.weight * phrases.count)
            }
            data.insert(phraseCountGenerator: generator)
            let exportURL = directory.appendingPathComponent("training.bin")
            try await data.export(to: exportURL)
            try await SFSpeechLanguageModel.prepareCustomLanguageModel(
                for: exportURL,
                configuration: configuration.makeConfiguration(),
                ignoresCache: false
            )
            try Data().write(to: readyMarker)
            SpeechDebugLog.write("custom LM prepared: \(phrases.count) terms")
            return true
        } catch {
            let nsError = error as NSError
            SpeechDebugLog.write(
                "custom LM failed: domain=\(nsError.domain) code=\(nsError.code)"
            )
            return false
        }
    }

    private static func makeHint(
        keyParts: [String]
    ) -> (directory: URL, configuration: SpeechLanguageModelHint) {
        let key = SHA256.hash(
            data: Data(keyParts.joined(separator: "\u{1F}").utf8)
        ).map { String(format: "%02x", $0) }.joined()
        let directory = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SpeechCustomLM/\(key)", isDirectory: true)
        return (
            directory,
            SpeechLanguageModelHint(
                languageModel: directory.appendingPathComponent("LM"),
                vocabulary: directory.appendingPathComponent("Vocab")
            )
        )
    }
}
