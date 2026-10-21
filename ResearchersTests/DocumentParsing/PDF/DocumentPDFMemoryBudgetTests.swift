import XCTest

@testable import Researchers

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
