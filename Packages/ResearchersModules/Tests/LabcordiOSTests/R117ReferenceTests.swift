import Foundation
@testable import LabcordiOS
import XCTest

private struct R117ReferenceFixture: Decodable {
    let text: String
    let language: String
    let expectedTerms: [String]
    let featureRows: [R117ReferenceRow]
    let canonicalPool: R117ReferencePool?

    enum CodingKeys: String, CodingKey {
        case text, language, expectedTerms
        case featureRows = "feature_rows"
        case canonicalPool = "canonical_pool_record"
    }
}

private struct R117ReferenceRow: Decodable {
    let text: String
    let start: Int
    let end: Int
}

private struct R117ReferencePool: Decodable {
    struct Raw: Decodable {
        let start: Int
        let end: Int
        let score: Double
        let kind: String
        let tier: Int
        let retained: Bool
    }
    struct Hint: Decodable { let text: String }
    let rawCandidates: [Raw]
    let native: [Hint]
    let guarded: [Hint]
}

final class R117ReferenceTests: XCTestCase {
    private func fixture() throws -> R117ReferenceFixture {
        guard let url = Bundle.module.url(
            forResource: "reference", withExtension: "json", subdirectory: "Fixtures"
        ) else { throw XCTSkip("Saved compressed reference fixture was not supplied") }
        return try JSONDecoder().decode(R117ReferenceFixture.self, from: Data(contentsOf: url))
    }

    func testCandidatePoolMatchesSavedFeatureOrder() async throws {
        let reference = try fixture()
        let directory = try XCTUnwrap(R117TermExtractor.resourceDirectory)
        let generator = R117NativeCandidateGenerator(resourceDirectory: directory)
        let pool = try await generator.generate(text: reference.text, language: reference.language)
        let groups = try R117ShortlistBuilder.build(source: reference.text, pool: pool)
        XCTAssertEqual(groups.count, reference.featureRows.count)
        let actual = try groups.map { group -> String in
            let mention = try XCTUnwrap(group.featureMention)
            return "\(mention.start):\(mention.end):\(mention.surface)"
        }
        let expected = reference.featureRows.map { "\($0.start):\($0.end):\($0.text)" }
        let mismatchCount = zip(actual, expected).filter { $0 != $1 }.count
        XCTAssertEqual(mismatchCount, 0, "Feature-row order differs from the saved pool")
    }

    func testGroupingSavedCanonicalPoolMatchesFeatureOrder() throws {
        let reference = try fixture()
        let saved = try XCTUnwrap(reference.canonicalPool)
        let pool = R117NativeCandidatePool(
            rawCandidates: saved.rawCandidates.map {
                R117NativeRawCandidate(start: $0.start, end: $0.end, score: $0.score,
                                       kind: $0.kind, tier: $0.tier, retained: $0.retained)
            }, nativeOrder: saved.native.map(\.text), guardedOrder: saved.guarded.map(\.text)
        )
        let groups = try R117ShortlistBuilder.build(source: reference.text, pool: pool)
        XCTAssertEqual(groups.count, reference.featureRows.count)
        let actual = try groups.map { group -> String in
            let mention = try XCTUnwrap(group.featureMention)
            return "\(mention.start):\(mention.end):\(mention.surface)"
        }
        let expected = reference.featureRows.map { "\($0.start):\($0.end):\($0.text)" }
        XCTAssertEqual(zip(actual, expected).filter { $0 != $1 }.count, 0)
    }

    func testNativePoolDiagnosticAgainstSavedRecord() async throws {
        let reference = try fixture()
        let saved = try XCTUnwrap(reference.canonicalPool)
        let directory = try XCTUnwrap(R117TermExtractor.resourceDirectory)
        let pool = try await R117NativeCandidateGenerator(resourceDirectory: directory)
            .generate(text: reference.text, language: reference.language)
        func key(_ start: Int, _ end: Int, _ kind: String, _ tier: Int) -> String {
            "\(start):\(end):\(kind):\(tier)"
        }
        let actual = Dictionary(grouping: pool.rawCandidates) {
            key($0.start, $0.end, $0.kind, $0.tier)
        }.mapValues { $0.map(\.score).sorted() }
        let expected = Dictionary(grouping: saved.rawCandidates) {
            key($0.start, $0.end, $0.kind, $0.tier)
        }.mapValues { $0.map(\.score).sorted() }
        XCTAssertEqual(pool.rawCandidates.count, saved.rawCandidates.count)
        XCTAssertEqual(Set(actual.keys), Set(expected.keys))
        let maximum = actual.keys.reduce(0.0) { largest, key in
            let differences = zip(actual[key] ?? [], expected[key] ?? []).map { abs($0 - $1) }
            return max(largest, differences.max() ?? 0)
        }
        print("Native raw-score maximum absolute difference: \(maximum)")
        print("Native order matches: \(pool.nativeOrder == saved.native.map(\.text))")
        print("Guarded order matches: \(pool.guardedOrder == saved.guarded.map(\.text))")
    }

    /// 참조 원문은 저장소에 넣지 않고 검증 실행 시 외부 fixture로 전달합니다.
    func testSavedCompressedSeed42Final50() async throws {
        let fixture = try fixture()
        let result = try await R117TermExtractor.shared.extract(from: fixture.text)
        let attachment = XCTAttachment(
            data: try JSONEncoder().encode(result), uniformTypeIdentifier: "public.json"
        )
        attachment.name = "R117 actual final50"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(result, fixture.expectedTerms)
    }
}
