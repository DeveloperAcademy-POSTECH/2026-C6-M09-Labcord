import Foundation
@testable import LabcordiOS
import XCTest

final class ProtocolClassificationResumeTests: XCTestCase {
    func testCompletedCheckpointPreservesCategoriesAndFallback() async throws {
        let seed = ProtocolExtractedTerms(materials: ["Aspirin"], glossaryTerms: ["reaction"],
                                          usedFallback: true)
        let result = try await ProtocolTermClassifier.classify(
            ["Aspirin", "reaction"], context: "Aspirin reaction", seed: seed
        ) { _ in XCTFail("A completed checkpoint must not repeat a batch") }
        XCTAssertEqual(result, seed)
    }

    func testCheckpointMustRepresentOriginalPrefix() async {
        let seed = ProtocolExtractedTerms(materials: ["reaction"])
        do {
            _ = try await ProtocolTermClassifier.classify(
                ["Aspirin", "reaction"], context: "Aspirin reaction", seed: seed
            ) { _ in XCTFail("An invalid checkpoint must not be saved") }
            XCTFail("Expected invalid checkpoint")
        } catch ProtocolTermClassifier.ClassificationError.invalidCheckpoint {
            // A later term cannot stand in for an earlier unfinished batch.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
