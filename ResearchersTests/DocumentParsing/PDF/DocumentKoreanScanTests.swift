import Foundation
import XCTest

@testable import Researchers

/// 한국어 125쪽 스캔의 해시·페이지·기준 문구를 확인한다. 성능 측정이나 전체 문자 오류율 검사는 아니다.
final class DocumentKoreanScanTests: XCTestCase {
  func testOriginalKoreanScanReleasePerformanceAndAnchors() async throws {
    executionTimeAllowance = 900
    let url = try DocumentScanStressSupport.url("korean-1992")
    try DocumentKoreanScanAssertions.verifyOriginal(url)
    let result = try await DocumentParser.parse(
      .url(url), options: .init(
        extractImages: true, performOCR: true,
        maximumConcurrentPDFPages: 6))
    try DocumentScanStressSupport.check(result, pages: 125)
    DocumentKoreanScanAssertions.verifyResult(result)
  }
}
