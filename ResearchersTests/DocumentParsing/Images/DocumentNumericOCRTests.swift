import CoreGraphics
import Foundation
import XCTest

@testable import Researchers

/// 숫자·통화 기호의 재인식 조건과 원본 스크린샷의 부분 정답을 확인한다. 모든 숫자 오류의 보정을 의미하지 않는다.
final class DocumentNumericOCRTests: XCTestCase {
  func testCharacterErrorRateCountsCurrencySubstitutions() {
    XCTAssertEqual(distance("$661.37", "S661.37"), 1)
    XCTAssertEqual(distance("$5,661.37", "55,661.37"), 1)
    XCTAssertEqual(distance("123.45", "12345"), 1)
    XCTAssertEqual(distance("", "12"), 2)
    XCTAssertEqual(distance("12", ""), 2)
  }

  func testOriginalLoanScreenshotCurrencyAccuracy() async throws {
    let url = try XCTUnwrap(Bundle(for: Self.self).url(
      forResource: "real-jpeg-03-loancalc", withExtension: "jpg",
      subdirectory: "RealWorld/jpeg"))
    let result = try await DocumentParser.parse(.url(url))
    // 원본 600×342 화면을 육안 대조한 금액 3개. 좌표는 좌상단 원점의 정규화 영역이다.
    let targets: [(String, CGRect)] = [
      ("$94.36", CGRect(x: 0.47, y: 0.64, width: 0.11, height: 0.06)),
      ("$661.37", CGRect(x: 0.47, y: 0.76, width: 0.11, height: 0.06)),
      ("$5,661.37", CGRect(x: 0.46, y: 0.82, width: 0.12, height: 0.06))
    ]
    var rows: [[String: Any]] = []
    var exact = 0
    var edits = 0
    for (index, target) in targets.enumerated() {
      let observed = result.blocks.filter {
        guard let bounds = $0.location.bounds else { return false }
        return target.1.contains(CGPoint(x: bounds.midX, y: bounds.midY))
      }.map(\.text).joined()
      XCTAssertFalse(observed.isEmpty, "currency-region[\(index)]")
      let errorCount = distance(target.0, observed)
      edits += errorCount
      if observed == target.0 { exact += 1 }
      rows.append([
        "region": index, "expected": target.0, "observed": observed,
        "editDistance": errorCount,
        "characterErrorRate": Double(errorCount) / Double(target.0.count)
      ])
    }
    let report: [String: Any] = [
      "fixture": "real-jpeg-03", "metric": "pixel-verified-currency-with-original",
      "exactMatches": exact, "targets": targets.count, "edits": edits, "regions": rows
    ]
    let attachment = XCTAttachment(
      data: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
      uniformTypeIdentifier: "public.json")
    attachment.name = "numeric-ocr-accuracy"
    attachment.lifetime = .keepAlways
    add(attachment)
    // 이 공개 샘플의 회귀 합격선이며 일반 문서의 통화 정확도 보장은 아니다.
    XCTAssertEqual(rows.count, 3)
    XCTAssertEqual(exact, 3)
    XCTAssertEqual(edits, 0)
    // OS·기기에서 최초 인식이 개선되면 보완 횟수가 줄어도 정상이다.
    for block in result.blocks where block.ocrOriginalText != nil {
      let original = try XCTUnwrap(block.ocrOriginalText)
      XCTAssertNotEqual(original, block.text)
      XCTAssertEqual(original.dropFirst(), block.text.dropFirst())
      XCTAssertEqual(block.text.first, "$")
    }
  }

  func testRefinementRequiresPixelEvidenceMatchingSuffixAndConfidence() {
    XCTAssertTrue(DocumentNumericOCR.accepts(
      "S661.37", confidence: 0.3, alternative: "$661.37", alternativeConfidence: 0.3))
    XCTAssertFalse(DocumentNumericOCR.accepts(
      "5661.37", confidence: 0.5, alternative: "$661.32", alternativeConfidence: 1))
    XCTAssertFalse(DocumentNumericOCR.accepts(
      "S661.37", confidence: 0.5, alternative: "$661.37", alternativeConfidence: 0.3))
    XCTAssertFalse(DocumentNumericOCR.accepts(
      "12345.67", confidence: 0.3, alternative: "$2345.67", alternativeConfidence: 1))
    XCTAssertFalse(DocumentNumericOCR.accepts(
      "S661.37", confidence: 0.3, alternative: "5661.37", alternativeConfidence: 1))
  }

  func testGeneratedNumericImagePreservesDigits() async throws {
    let image = try XCTUnwrap(DocumentImageFixtures.textImage("12345.67"))
    let result = try await DocumentParser.parse(.image(image, orientation: .up))
    XCTAssertEqual(result.fullText.trimmingCharacters(in: .whitespacesAndNewlines), "12345.67")
  }

  private func distance(_ expected: String, _ actual: String) -> Int {
    let lhs = Array(expected)
    let rhs = Array(actual)
    var previous = Array(0...rhs.count)
    for (row, character) in lhs.enumerated() {
      var current = [row + 1]
      for (column, other) in rhs.enumerated() {
        current.append(min(
          current[column] + 1, previous[column + 1] + 1,
          previous[column] + (character == other ? 0 : 1)))
      }
      previous = current
    }
    return previous[rhs.count]
  }
}
