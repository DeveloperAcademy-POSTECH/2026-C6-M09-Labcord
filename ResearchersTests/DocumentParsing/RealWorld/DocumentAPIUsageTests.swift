import CoreGraphics
import Foundation
import ImageIO
import Synchronization
import UniformTypeIdentifiers
import XCTest

@testable import Researchers

/// URL·Data·CGImage·혼합 배치·취소의 공개 API와 형식별 부분 정답을 확인한다.
final class DocumentAPIUsageTests: XCTestCase {
  func testURLAndDataExamplesAcrossAllFormats() async throws {
    let fixtures = try loadFixtures()
    XCTAssertEqual(fixtures.count, 60)
    XCTAssertEqual(Set(fixtures.map(\.format)).count, 20)
    for fixture in fixtures {
      let url = try resourceURL(fixture.filename, format: fixture.format)
      await verifyInput(.url(url), fixture: fixture, mode: "url")
      await verifyInput(.data(try Data(contentsOf: url), fileName: fixture.filename),
                        fixture: fixture, mode: "data")
    }
  }

  func testMixedBatchExamplePreservesOrderAndFailures() async throws {
    let groups = Dictionary(grouping: try loadFixtures(), by: \.format)
    let fixtures = groups.keys.sorted().compactMap { groups[$0]?.first }
    XCTAssertEqual(fixtures.count, 20)
    var inputs: [DocumentInput] = try fixtures.enumerated().map { index, fixture in
      let url = try resourceURL(fixture.filename, format: fixture.format)
      return index.isMultiple(of: 2) ? .url(url)
        : .data(try Data(contentsOf: url), fileName: fixture.filename)
    }
    let image = try XCTUnwrap(DocumentImageFixtures.textImage("LABCORD 사용법 123"))
    inputs.append(.image(image, orientation: .up))
    inputs.append(.data(Data("%PDF-1.7\n".utf8), fileName: "damaged.pdf"))
    let progress = Mutex<[DocumentProgress]>([])
    let outcomes = try await DocumentParser.parseBatch(inputs, options: .init(
      extractImages: true, performOCR: true,
      maximumConcurrentDocuments: 2, maximumConcurrentPDFPages: 4)) { event in
      progress.withLock { $0.append(event) }
    }
    XCTAssertEqual(outcomes.count, inputs.count)
    try checkBatch(outcomes, fixtures: fixtures)
    validateProgress(progress.withLock { $0 }, count: inputs.count)
  }

  func testCGImageExampleReturnsKoreanEnglishTextAndLocations() async throws {
    let image = try XCTUnwrap(DocumentImageFixtures.textImage("LABCORD 사용법 123"))
    let result = try await DocumentParser.parse(.image(image, orientation: .up),
      options: .init(extractImages: true, performOCR: true))
    XCTAssertEqual(result.format, .image)
    verifyImageText(result)
    XCTAssertTrue(result.blocks.filter { $0.kind == .imageOCR }.allSatisfy {
      $0.kind == .imageOCR && $0.location.bounds != nil && $0.ocrConfidence != nil
    })
  }

  func testTextImageFilesAcrossFourEncodings() async throws {
    let image = try XCTUnwrap(DocumentImageFixtures.textImage("LABCORD 사용법 123"))
    let formats: [(DocumentFormat, String)] = [
      (.jpeg, UTType.jpeg.identifier), (.png, UTType.png.identifier),
      (.heic, UTType.heic.identifier), (.tiff, UTType.tiff.identifier)
    ]
    for (format, identifier) in formats {
      let data = NSMutableData()
      let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
        data, identifier as CFString, 1, nil))
      CGImageDestinationAddImage(destination, image, nil)
      XCTAssertTrue(CGImageDestinationFinalize(destination))
      let result = try await DocumentParser.parse(
        .data(data as Data, fileName: "generated.\(format.rawValue)"),
        options: .init(extractImages: true, performOCR: true))
      XCTAssertEqual(result.format, format)
      verifyImageText(result)
    }
  }

  func testTaskCancellationExample() async throws {
    let task = Task {
      try await DocumentParser.parse(.data(Data("example".utf8), fileName: "example.txt"),
        options: .init(extractImages: true, performOCR: true))
    }
    task.cancel()
    do {
      _ = try await task.value
      XCTFail("Cancelled task unexpectedly returned a document")
    } catch {
      XCTAssertTrue(error is CancellationError || (error as? DocumentParsingError) == .cancelled)
    }
  }

  private func verifyInput(_ input: DocumentInput, fixture: Fixture, mode: String) async {
    do {
      let result = try await DocumentParser.parse(input,
        options: .init(extractImages: true, performOCR: true))
      try verify(result, fixture: fixture)
    } catch {
      let name = (error as? DocumentParsingError).map { String(describing: $0) }
        ?? String(reflecting: type(of: error))
      XCTFail("\(fixture.id) \(mode): \(name)")
    }
  }

  private func checkBatch(_ outcomes: [DocumentBatchResult], fixtures: [Fixture]) throws {
    for (index, outcome) in outcomes.enumerated() {
      switch outcome {
      case .success(let result):
        XCTAssertLessThan(index, fixtures.count + 1)
        if index < fixtures.count { try verify(result, fixture: fixtures[index]) }
        if index == fixtures.count { verifyImageText(result) }
      case .failure(let error):
        XCTAssertEqual(index, fixtures.count + 1)
        XCTAssertEqual(error, .malformedDocument)
      }
    }
  }

  private func verify(_ result: DocumentParseResult, fixture: Fixture) throws {
    XCTAssertEqual(result.format.rawValue, fixture.format, fixture.id)
    XCTAssertEqual(result.blocks.map(\.readingOrder), Array(result.blocks.indices), fixture.id)
    let kinds: [DocumentBlockKind] = [.paragraph, .heading, .tableCell, .imageOCR]
    let text = result.blocks.filter { kinds.contains($0.kind) }
      .map(\.text).filter { !$0.isEmpty }.joined(separator: "\n")
    XCTAssertTrue(result.fullText == text, fixture.id)
    try DocumentGoldenAssertions.verify(result, id: fixture.id, sha256: fixture.sha256)
  }

  private func verifyImageText(_ result: DocumentParseResult) {
    XCTAssertTrue(result.fullText.contains("LABCORD"))
    XCTAssertTrue(result.fullText.contains("사용법"))
    XCTAssertTrue(result.fullText.contains("123"))
  }

  private func validateProgress(_ events: [DocumentProgress], count: Int) {
    for index in 0..<count {
      let sequence = events.filter { $0.inputIndex == index }
      XCTAssertEqual(sequence.first?.phase, .identifying)
      XCTAssertEqual(sequence.last?.phase, index == count - 1 ? .failed : .completed)
      XCTAssertEqual(sequence.last?.fractionCompleted, 1)
      let fractions = sequence.map(\.fractionCompleted)
      XCTAssertTrue(zip(fractions, fractions.dropFirst()).allSatisfy { $0.0 <= $0.1 })
    }
  }

  private func resourceURL(_ filename: String, format: String? = nil) throws -> URL {
    let name = filename as NSString
    return try XCTUnwrap(Bundle(for: Self.self).url(
      forResource: name.deletingPathExtension, withExtension: name.pathExtension,
      subdirectory: format.map { "RealWorld/\($0)" } ?? "RealWorld"))
  }

  private func loadFixtures() throws -> [Fixture] {
    let url = try resourceURL("RealWorldManifest.json")
    return try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: url))
  }

  private struct Fixture: Decodable {
    let id: String
    let filename: String
    let format: String
    let sha256: String
  }
}
