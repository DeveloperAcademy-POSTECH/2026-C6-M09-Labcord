import CoreGraphics
import Foundation
import ImageIO
import Synchronization
import UniformTypeIdentifiers
import XCTest

@testable import Researchers

/// 공개 Swift 사용 예제를 URL·Data·CGImage·혼합 배치·취소로 실행한다. 형식별 부분 정답과 실제 경고도 함께 확인한다.
final class DocumentAPIUsageTests: XCTestCase {
  func testURLAndDataExamplesAcrossAllFormats() async throws {
    let fixtures = try loadFixtures()
    XCTAssertEqual(fixtures.count, 60)
    XCTAssertEqual(Set(fixtures.map(\.format)).count, 20)
    var rows: [[String: Any]] = []
    for fixture in fixtures {
      let url = try resourceURL(fixture.filename, format: fixture.format)
      rows.append(await parseAndRecord(.url(url), fixture: fixture, mode: "url"))
      rows.append(await parseAndRecord(
        .data(try Data(contentsOf: url), fileName: fixture.filename),
        fixture: fixture, mode: "data"))
    }
    try attach(rows, name: "api-usage-single-inputs")
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
    var options = DocumentParserOptions()
    options.maximumConcurrentDocuments = 2
    options.maximumConcurrentPDFPages = 4
    options.pdfWorkingMemoryTargetBytes = 256 * 1024 * 1024
    let progress = Mutex<[DocumentProgress]>([])
    let start = ContinuousClock.now
    let outcomes = try await DocumentParser.parseBatch(inputs, options: options) { event in
      progress.withLock { $0.append(event) }
    }
    XCTAssertEqual(outcomes.count, inputs.count)
    let rows = try batchRows(outcomes, fixtures: fixtures)
    let progressValid = validateProgress(progress.withLock { $0 }, count: inputs.count)
    try attach([
      "seconds": DocumentFootprint.seconds(start.duration(to: .now)),
      "inputs": rows, "progressValid": progressValid
    ], name: "api-usage-mixed-batch")
  }

  func testCGImageExampleReturnsKoreanEnglishTextAndLocations() async throws {
    let image = try XCTUnwrap(DocumentImageFixtures.textImage("LABCORD 사용법 123"))
    let result = try await DocumentParser.parse(.image(image, orientation: .up))
    XCTAssertEqual(result.format, .image)
    verifyImageText(result)
    XCTAssertTrue(result.blocks.allSatisfy {
      $0.kind == .imageOCR && $0.location.bounds != nil && $0.ocrConfidence != nil
    })
    try attach(summary(result), name: "api-usage-cgimage")
  }

  func testTextImageFilesAcrossFourEncodings() async throws {
    let image = try XCTUnwrap(DocumentImageFixtures.textImage("LABCORD 사용법 123"))
    let formats: [(DocumentFormat, String)] = [
      (.jpeg, UTType.jpeg.identifier), (.png, UTType.png.identifier),
      (.heic, UTType.heic.identifier), (.tiff, UTType.tiff.identifier)
    ]
    var rows: [[String: Any]] = []
    for (format, identifier) in formats {
      let data = NSMutableData()
      let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
        data, identifier as CFString, 1, nil))
      CGImageDestinationAddImage(destination, image, nil)
      XCTAssertTrue(CGImageDestinationFinalize(destination))
      let result = try await DocumentParser.parse(
        .data(data as Data, fileName: "generated.\(format.rawValue)"))
      XCTAssertEqual(result.format, format)
      verifyImageText(result)
      var row = summary(result)
      row["inputBytes"] = data.length
      rows.append(row)
    }
    try attach(rows, name: "api-usage-generated-image-files")
  }

  func testTaskCancellationExample() async throws {
    let task = Task {
      try await DocumentParser.parse(.data(Data("example".utf8), fileName: "example.txt"))
    }
    task.cancel()
    do {
      _ = try await task.value
      XCTFail("Cancelled task unexpectedly returned a document")
    } catch DocumentParsingError.cancelled {
      try attach(["cancelled": true], name: "api-usage-cancellation")
    } catch is CancellationError {
      try attach(["cancelled": true], name: "api-usage-cancellation")
    }
  }

  private func parseAndRecord(
    _ input: DocumentInput, fixture: Fixture, mode: String
  ) async -> [String: Any] {
    let start = ContinuousClock.now
    do {
      let result = try await DocumentParser.parse(input)
      try verify(result, fixture: fixture)
      var row = summary(result)
      row["id"] = fixture.id
      row["mode"] = mode
      row["seconds"] = DocumentFootprint.seconds(start.duration(to: .now))
      row["success"] = true
      return row
    } catch {
      let category = error as? DocumentParsingError
      let name = category.map { String(describing: $0) } ?? String(reflecting: type(of: error))
      XCTFail("\(fixture.id) \(mode): \(name)")
      return ["id": fixture.id, "mode": mode, "success": false, "error": name]
    }
  }

  private func batchRows(
    _ outcomes: [DocumentBatchResult], fixtures: [Fixture]
  ) throws -> [[String: Any]] {
    try outcomes.enumerated().map { index, outcome in
      switch outcome {
      case .success(let result):
        XCTAssertLessThan(index, fixtures.count + 1)
        if index < fixtures.count { try verify(result, fixture: fixtures[index]) }
        if index == fixtures.count { verifyImageText(result) }
        var row = summary(result)
        row["index"] = index
        row["id"] = index < fixtures.count ? fixtures[index].id : "generated-image"
        row["success"] = true
        return row
      case .failure(let error):
        XCTAssertEqual(index, fixtures.count + 1)
        XCTAssertEqual(error, .malformedDocument)
        return ["index": index, "success": false, "error": String(describing: error)]
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

  private func validateProgress(_ events: [DocumentProgress], count: Int) -> Bool {
    var valid = true
    for index in 0..<count {
      let sequence = events.filter { $0.inputIndex == index }
      XCTAssertEqual(sequence.first?.phase, .identifying)
      XCTAssertEqual(sequence.last?.phase, index == count - 1 ? .failed : .completed)
      XCTAssertEqual(sequence.last?.fractionCompleted, 1)
      let fractions = sequence.map(\.fractionCompleted)
      let monotonic = zip(fractions, fractions.dropFirst()).allSatisfy { $0.0 <= $0.1 }
      XCTAssertTrue(monotonic)
      valid = valid && monotonic && sequence.first?.phase == .identifying
        && sequence.last?.phase == (index == count - 1 ? .failed : .completed)
        && sequence.last?.fractionCompleted == 1
    }
    return valid
  }

  private func summary(_ result: DocumentParseResult) -> [String: Any] {
    [
      "format": result.format.rawValue, "textCharacters": result.fullText.count,
      "blocks": result.blocks.count, "tableCells": result.blocks.filter {
        $0.kind == .tableCell
      }.count,
      "ocrBlocks": result.blocks.filter { $0.kind == .imageOCR }.count,
      "images": result.images.count,
      "warningCodes": result.warnings.map { $0.code.rawValue },
      "blocksSHA256": DocumentResultFingerprint.blocks(result.blocks),
      "imagesSHA256": DocumentResultFingerprint.images(result.images),
      "warningsSHA256": DocumentResultFingerprint.warnings(result.warnings)
    ]
  }

  private func attach(_ value: Any, name: String) throws {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
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
