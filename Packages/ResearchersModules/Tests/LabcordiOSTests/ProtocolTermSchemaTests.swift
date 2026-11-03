import Foundation
import FoundationModels
@testable import LabcordiOS
import XCTest

final class ProtocolTermSchemaTests: XCTestCase {
    func testPropertyOrderDoesNotChangeTermAssociation() throws {
        let content = try GeneratedContent(json: """
            {"교반기":"material","mM":"unit","시료":"sample"}
            """)
        let result = ProtocolTermClassifier.labels(from: content, terms: ["시료", "mM", "교반기"])
        XCTAssertEqual(result.labels.map(\.term), ["시료", "mM", "교반기"])
        guard case .sample = result.labels[0].category,
              case .unit = result.labels[1].category,
              case .material = result.labels[2].category else {
            return XCTFail("키 대신 응답 순서로 분류를 연결함")
        }
    }

    func testMissingOrInvalidCategoryIsNotAssignedToAnotherTerm() throws {
        let content = try GeneratedContent(json: """
            {"아스피린":"material","mL":"invalid"}
            """)
        let result = ProtocolTermClassifier.labels(
            from: content, terms: ["아스피린", "시료", "mL"]
        )
        XCTAssertEqual(result.labels.map(\.term), ["아스피린"])
    }

    func testUnexpectedPropertiesAndNonobjectResponsesAreRejected() throws {
        for json in [#"{"시약":"material","없는 용어":"sample"}"#, #"["material"]"#] {
            let result = ProtocolTermClassifier.labels(
                from: try GeneratedContent(json: json), terms: ["시약"]
            )
            XCTAssertTrue(result.labels.isEmpty)
        }
    }

    func testSchemaAndCodecPreserveSpecialCharactersAndExactSourceKeys() throws {
        let terms = ["가열교반기(Hot plate)", "85% 인산", "A\"B\\C", "μL", "mM", "mm"]
        _ = try ProtocolTermClassifier.classificationSchema(terms)
        let json = try JSONSerialization.data(withJSONObject: Dictionary(
            uniqueKeysWithValues: terms.map { ($0, "material") }
        ))
        let string = try XCTUnwrap(String(data: json, encoding: .utf8))
        let content = try GeneratedContent(json: string)
        let labels = ProtocolTermClassifier.labels(from: content, terms: terms)
        XCTAssertEqual(labels.labels.map(\.term), terms)
    }
}
