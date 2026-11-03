import CryptoKit
import Foundation
@testable import LabcordiOS
import OmniParser
import XCTest

final class ProtocolAnalysisJobStoreTests: XCTestCase {
    func testPrepareCopiesInputWithoutChangingOriginalBytes() throws {
        try withTemporaryStore { store, directory in
            let source = directory.appendingPathComponent("원본.pdf")
            let data = Data("합성 프로토콜: 30초간 교반".utf8)
            try data.write(to: source)
            let input = ProtocolAnalysisJobInput(
                id: UUID(), url: source, name: "원본.pdf", isPhoto: false
            )
            let record = try store.prepare(id: UUID(), inputs: [input], now: Date())
            let copied = try XCTUnwrap(store.inputs(record).first)
            let originalBytes = try Data(contentsOf: source)
            let copiedBytes = try Data(contentsOf: copied.url)

            XCTAssertNotEqual(copied.url, source)
            XCTAssertEqual(originalBytes, data)
            XCTAssertEqual(SHA256.hash(data: copiedBytes), SHA256.hash(data: originalBytes))
            XCTAssertEqual(copied.id, input.id)
            XCTAssertEqual(copied.name, input.name)
            XCTAssertFalse(copied.isPhoto)
            XCTAssertEqual(record.status, .queued)
            try Data("새 원본".utf8).write(to: source)
            XCTAssertEqual(try Data(contentsOf: copied.url), data)
        }
    }

    func testDuplicateJobIDDoesNotOverwriteSavedInputOrCheckpoint() throws {
        try withTemporaryStore { store, directory in
            let source = directory.appendingPathComponent("사진.png")
            let data = Data("합성 이미지 바이트".utf8)
            try data.write(to: source)
            let input = ProtocolAnalysisJobInput(
                id: UUID(), url: source, name: "사진.png", isPhoto: true
            )
            let record = try store.prepare(id: UUID(), inputs: [input], now: Date())
            let checkpoint = checkpointURL(store, record)
            let saved = try Data(contentsOf: checkpoint)
            let copied = try XCTUnwrap(store.inputs(record).first)

            XCTAssertThrowsError(try store.prepare(id: record.id, inputs: [input], now: Date()))
            XCTAssertEqual(try Data(contentsOf: checkpoint), saved)
            XCTAssertEqual(try Data(contentsOf: copied.url), data)
            XCTAssertEqual(try Data(contentsOf: source), data)
            XCTAssertTrue(copied.isPhoto)
        }
    }

    func testSavedDocumentRoundTripPreservesSourceMetadataAndWarnings() throws {
        let document = sourceDocument()
        let data = try JSONEncoder().encode(ProtocolAnalysisSavedDocument(document))
        let saved = try JSONDecoder().decode(ProtocolAnalysisSavedDocument.self, from: data)
        let restored = try saved.restored()

        XCTAssertEqual(restored, document)
        XCTAssertEqual(restored.blocks.map(\.kind), [.paragraph, .tableCell, .imageOCR])
        XCTAssertEqual(restored.blocks[1].location.rowSpan, 2)
        XCTAssertEqual(restored.blocks[1].location.columnSpan, 3)
        XCTAssertEqual(restored.blocks[2].ocrConfidence, 0.875)
        XCTAssertEqual(restored.blocks[2].ocrOriginalText, "Aspinn")
        XCTAssertEqual(restored.warnings.map(\.code), [.uncertainReadingOrder, .imageOCRFailed])
    }

    func testSaveAndLatestRestorePartialAnalysisForResuming() throws {
        try withTemporaryStore { store, _ in
            var record = try store.prepare(
                id: UUID(), inputs: [], now: Date(timeIntervalSince1970: 1)
            )
            let inputID = UUID().uuidString
            let terms = ProtocolExtractedTerms(materials: ["아스피린"], usedFallback: true)
            record.status = .paused
            record.updatedAt = Date(timeIntervalSince1970: 2)
            record.message = "앱으로 돌아오면 계속 분석해요."
            record.documents[inputID] = ProtocolAnalysisSavedDocument(sourceDocument())
            record.selected[inputID] = ["아스피린", "교반"]
            record.classified[inputID] = ProtocolAnalysisSavedTerms(terms)
            record.finished.insert(inputID)
            try store.save(record)

            let restored = try XCTUnwrap(store.latest())
            XCTAssertEqual(restored.id, record.id)
            XCTAssertEqual(restored.status, .paused)
            XCTAssertEqual(restored.createdAt, record.createdAt)
            XCTAssertEqual(restored.updatedAt, record.updatedAt)
            XCTAssertEqual(restored.message, record.message)
            XCTAssertEqual(try restored.documents[inputID]?.restored(), sourceDocument())
            XCTAssertEqual(restored.selected[inputID], ["아스피린", "교반"])
            XCTAssertEqual(restored.classified[inputID]?.restored, terms)
            XCTAssertEqual(restored.finished, [inputID])
        }
    }

    func testCancelledNewestJobDoesNotRestoreAnOlderDraftOrDeleteCheckpoints() throws {
        try withTemporaryStore { store, _ in
            var paused = try store.prepare(
                id: UUID(), inputs: [], now: Date(timeIntervalSince1970: 1)
            )
            paused.status = .paused
            try store.save(paused)
            var cancelled = try store.prepare(
                id: UUID(), inputs: [], now: Date(timeIntervalSince1970: 2)
            )
            cancelled.status = .cancelled
            try store.save(cancelled)

            XCTAssertNil(try store.latest())
            let cancelledCheckpoint = checkpointURL(store, cancelled)
            XCTAssertTrue(FileManager.default.fileExists(atPath: cancelledCheckpoint.path))
        }
    }

    func testLatestReturnsNewestCompletedJobAndCancelledOnlyReturnsNil() throws {
        try withTemporaryStore { store, _ in
            var first = try store.prepare(
                id: UUID(), inputs: [], now: Date(timeIntervalSince1970: 1)
            )
            first.status = .cancelled
            try store.save(first)
            XCTAssertNil(try store.latest())
            var completed = try store.prepare(
                id: UUID(), inputs: [], now: Date(timeIntervalSince1970: 2)
            )
            completed.status = .completed
            try store.save(completed)

            XCTAssertEqual(try store.latest()?.id, completed.id)
            XCTAssertEqual(try store.latest()?.status, .completed)
        }
    }

    func testInvalidCheckpointJSONIsRejectedAndPreserved() throws {
        try withTemporaryStore { store, _ in
            let record = try store.prepare(id: UUID(), inputs: [], now: Date())
            let url = checkpointURL(store, record)
            let invalid = Data("{\"version\":1,\"unfinished\":".utf8)
            try invalid.write(to: url)

            XCTAssertThrowsError(try store.latest())
            XCTAssertEqual(try Data(contentsOf: url), invalid)
        }
    }

    func testUnknownVersionAndMismatchedJobIDAreRejectedWithoutOverwriting() throws {
        for key in ["version", "id"] {
            try withTemporaryStore { store, _ in
                let record = try store.prepare(id: UUID(), inputs: [], now: Date())
                let url = checkpointURL(store, record)
                let data = try Data(contentsOf: url)
                var json = try XCTUnwrap(
                    JSONSerialization.jsonObject(with: data) as? [String: Any]
                )
                if key == "version" {
                    json[key] = 99
                } else {
                    json[key] = UUID().uuidString
                }
                let invalid = try JSONSerialization.data(withJSONObject: json)
                try invalid.write(to: url)

                XCTAssertThrowsError(try store.latest(), key)
                XCTAssertEqual(try Data(contentsOf: url), invalid)
            }
        }
    }

    func testInputPathTraversalIsRejectedWithoutChangingOutsideFile() throws {
        try withTemporaryStore { store, directory in
            let outside = directory.appendingPathComponent("outside.pdf")
            let original = Data("다른 파일".utf8)
            try original.write(to: outside)
            let record = try store.prepare(id: UUID(), inputs: [], now: Date())
            for fileName in ["../outside.pdf", "sub/input.pdf", outside.path, "..", ".", ""] {
                var invalid = record
                invalid.inputs = [.init(
                    id: UUID(), fileName: fileName, name: "표시 이름.pdf", isPhoto: false
                )]
                XCTAssertThrowsError(try store.inputs(invalid), fileName)
                XCTAssertEqual(try Data(contentsOf: outside), original)
            }
        }
    }

    func testUnsupportedDocumentMetadataIsRejected() throws {
        var invalid = ProtocolAnalysisSavedDocument(sourceDocument())
        invalid.format = "unknown-format"
        XCTAssertThrowsError(try invalid.restored())
        invalid = ProtocolAnalysisSavedDocument(sourceDocument())
        invalid.blocks[0].kind = "unknown-kind"
        XCTAssertThrowsError(try invalid.restored())
        invalid = ProtocolAnalysisSavedDocument(sourceDocument())
        invalid.warnings[0].code = "unknown-warning"
        XCTAssertThrowsError(try invalid.restored())
    }

    private func checkpointURL(
        _ store: ProtocolAnalysisJobStore, _ record: ProtocolAnalysisJobRecord
    ) -> URL {
        store.jobDirectory(record.id).appendingPathComponent("checkpoint.json")
    }

    private func withTemporaryStore(
        _ body: (ProtocolAnalysisJobStore, URL) throws -> Void
    ) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "labcord-analysis-store-\(UUID().uuidString)", isDirectory: true
            )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProtocolAnalysisJobStore(
            directory: directory.appendingPathComponent("jobs", isDirectory: true)
        )
        try body(store, directory)
    }

    private func sourceDocument() -> DocumentParseResult {
        let cell = DocumentLocation(
            part: "table-1", page: 2, row: 3, column: 4, paragraph: 5,
            bounds: CGRect(x: 0.25, y: 0.5, width: 0.125, height: 0.25), rowSpan: 2, columnSpan: 3
        )
        let image = DocumentLocation(
            part: "figure-1", page: 3,
            bounds: CGRect(x: 0.125, y: 0.25, width: 0.5, height: 0.125)
        )
        return DocumentParseResult(format: .pdf, blocks: [
            DocumentBlock(kind: .paragraph, text: "30초간 교반", readingOrder: 0,
                          location: DocumentLocation(page: 1, paragraph: 1)),
            DocumentBlock(kind: .tableCell, text: "아스피린", readingOrder: 1, location: cell),
            DocumentBlock(kind: .imageOCR, text: "Aspirin", readingOrder: 2, location: image,
                          ocrConfidence: 0.875, ocrOriginalText: "Aspinn")
        ], warnings: [
            DocumentWarning(code: .uncertainReadingOrder, message: "합성 표 경고", location: cell),
            DocumentWarning(code: .imageOCRFailed, message: "합성 문서 경고")
        ])
    }
}
