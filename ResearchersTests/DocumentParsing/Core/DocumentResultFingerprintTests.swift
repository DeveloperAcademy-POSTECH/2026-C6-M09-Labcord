import XCTest

@testable import Researchers

/// 위치·순서·신뢰도·PNG 바이트가 달라지면 지문도 달라지는지 확인해 전후 비교의 누락을 막는다.
final class DocumentResultFingerprintTests: XCTestCase {
  func testBlockFingerprintIncludesPositionOrderAndConfidence() {
    let block = DocumentBlock(
      kind: .imageOCR, text: "fixture", readingOrder: 0,
      location: .init(page: 1, bounds: .init(x: 0.1, y: 0.2, width: 0.3, height: 0.4)),
      ocrConfidence: 0.9)
    let original = DocumentResultFingerprint.blocks([block])
    let changes: [(inout DocumentBlock) -> Void] = [
      { $0.kind = .paragraph }, { $0.text += "!" }, { $0.readingOrder += 1 },
      { $0.location.page = 2 }, { $0.location.part = "" },
      { $0.location.row = 1 }, { $0.location.column = 1 },
      { $0.location.paragraph = 1 }, { $0.location.rowSpan = 2 },
      { $0.location.columnSpan = 2 }, { $0.location.bounds?.origin.x += 0.01 },
      { $0.location.bounds?.origin.y += 0.01 },
      { $0.location.bounds?.size.width += 0.01 },
      { $0.location.bounds?.size.height += 0.01 },
      { $0.ocrConfidence = 0.8 }, { $0.ocrOriginalText = "fixture" }
    ]
    for change in changes {
      var modified = block
      change(&modified)
      XCTAssertNotEqual(original, DocumentResultFingerprint.blocks([modified]))
    }
    XCTAssertEqual(original, DocumentResultFingerprint.blocks([block]))
  }

  func testImageAndWarningFingerprintsIncludeMetadataAndBytes() {
    let image = DocumentEmbeddedImage(id: "image", pngData: Data([1]), location: .init(page: 1))
    let original = DocumentResultFingerprint.images([image])
    let changes: [(inout DocumentEmbeddedImage) -> Void] = [
      { $0.id += "2" }, { $0.pngData.append(2) }, { $0.location.page = 2 },
      { $0.orientation = .down }, { $0.sourceDescription = "source" }
    ]
    for change in changes {
      var modified = image
      change(&modified)
      XCTAssertNotEqual(original, DocumentResultFingerprint.images([modified]))
    }
    let warning = DocumentWarning(code: .extractionFailed, message: "fixture")
    var modified = warning
    modified.location = .init(page: 1)
    XCTAssertNotEqual(DocumentResultFingerprint.warnings([warning]),
                      DocumentResultFingerprint.warnings([modified]))
    modified = warning
    modified.message += "!"
    XCTAssertNotEqual(DocumentResultFingerprint.warnings([warning]),
                      DocumentResultFingerprint.warnings([modified]))
  }
}
