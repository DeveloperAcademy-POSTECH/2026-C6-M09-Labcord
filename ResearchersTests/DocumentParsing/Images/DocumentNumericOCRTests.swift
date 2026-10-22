import CoreGraphics
import Foundation
import XCTest

@testable import Researchers

/// 숫자·통화 기호의 재인식 조건과 원본 스크린샷의 부분 정답을 확인한다. 모든 숫자 오류의 보정을 의미하지 않는다.
final class DocumentNumericOCRTests: XCTestCase {
  func testOriginalLoanScreenshotCurrencyAccuracy() async throws {
    let url = try XCTUnwrap(Bundle(for: Self.self).url(
      forResource: "real-jpeg-03-loancalc", withExtension: "jpg",
      subdirectory: "RealWorld/jpeg"))
    let result = try await DocumentParser.parse(.url(url),
      options: .init(extractImages: true, performOCR: true))
    // 원본 600×342 화면을 육안 대조한 금액 3개. 좌표는 좌상단 원점의 정규화 영역이다.
    let targets: [(String, CGRect)] = [
      ("$94.36", CGRect(x: 0.47, y: 0.64, width: 0.11, height: 0.06)),
      ("$661.37", CGRect(x: 0.47, y: 0.76, width: 0.11, height: 0.06)),
      ("$5,661.37", CGRect(x: 0.46, y: 0.82, width: 0.12, height: 0.06))
    ]
    for (index, target) in targets.enumerated() {
      let observed = result.blocks.filter {
        guard let bounds = $0.location.bounds else { return false }
        return target.1.contains(CGPoint(x: bounds.midX, y: bounds.midY))
      }.map(\.text).joined()
      XCTAssertFalse(observed.isEmpty, "currency-region[\(index)]")
      XCTAssertEqual(observed, target.0, "currency-region[\(index)]")
    }

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
    let result = try await DocumentParser.parse(.image(image, orientation: .up),
      options: .init(extractImages: true, performOCR: true))
    XCTAssertEqual(result.fullText.trimmingCharacters(in: .whitespacesAndNewlines), "12345.67")
  }

}
