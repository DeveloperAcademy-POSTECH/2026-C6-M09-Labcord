import Foundation
@testable import LabcordiOS
import XCTest

final class R117TokenizerTests: XCTestCase {
    func testMaskIncludesLeadingWhitespaceInSourceOffset() {
        let source = Array("A \t<mask>B".unicodeScalars)
        let token = R117AddedToken(content: "<mask>", id: 250_001,
                                  leftStrip: true, rightStrip: false)
        XCTAssertEqual(token.matchedRange(in: source, at: 3, lowerBound: 0), 1..<9)
    }

    func testStripDoesNotCrossPreviousAddedToken() {
        let source = Array("<unk>  <mask>".unicodeScalars)
        let token = R117AddedToken(content: "<mask>", id: 250_001,
                                  leftStrip: true, rightStrip: false)
        XCTAssertEqual(token.matchedRange(in: source, at: 7, lowerBound: 5), 5..<13)
    }

    func testNonStrippingTokenKeepsExactLiteralOffset() {
        let source = Array("A  <unk>  B".unicodeScalars)
        let token = R117AddedToken(content: "<unk>", id: 3,
                                  leftStrip: false, rightStrip: false)
        XCTAssertEqual(token.matchedRange(in: source, at: 3, lowerBound: 0), 3..<8)
    }

    func testRightStripIncludesWhitespaceAndStopsAtNextText() {
        let source = Array("<mask> \tB".unicodeScalars)
        let token = R117AddedToken(content: "<mask>", id: 250_001,
                                  leftStrip: false, rightStrip: true)
        XCTAssertEqual(token.matchedRange(in: source, at: 0, lowerBound: 0), 0..<8)
    }
}
