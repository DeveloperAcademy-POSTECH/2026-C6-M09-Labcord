import XCTest

@testable import Researchers

/// 단일 문서와 배치의 Vision 예약 여유가 올바른 호출 범위에만 적용되는지 확인한다.
final class DocumentPDFMemoryBudgetTests: XCTestCase {
  func testBatchReserveIncludesAdditionalVisionMemoryWithoutChangingStandaloneReserve() {
    XCTAssertEqual(DocumentPDFWorkingMemory.recognitionReserveBytes, 32 * 1024 * 1024)
    let pool = DocumentPDFWorkPool(options: .init())
    let batch = DocumentPDFScheduling.$pool.withValue(pool) {
      DocumentPDFWorkingMemory.recognitionReserveBytes
    }
    XCTAssertEqual(batch, 48 * 1024 * 1024)
    XCTAssertEqual(DocumentPDFWorkingMemory.recognitionReserveBytes, 32 * 1024 * 1024)
  }
}
