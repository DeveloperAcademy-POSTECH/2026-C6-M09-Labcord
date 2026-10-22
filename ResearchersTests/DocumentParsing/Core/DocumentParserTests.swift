import Foundation
import Synchronization
import XCTest

@testable import Researchers

/// 외부 호출자가 의존하는 실행 문맥·배치 순서·개별 실패·취소 이벤트 계약을 확인한다.
final class DocumentParserTests: XCTestCase {
  @MainActor
  func testParsingLeavesMainActorBeforeReportingProgress() async throws {
    XCTAssertTrue(Thread.isMainThread)
    let input = DocumentInput.data(Data("Background".utf8), fileName: "input.txt")
    _ = try await DocumentParser.parse(input) { _ in
      XCTAssertFalse(Thread.isMainThread)
    }
    XCTAssertTrue(Thread.isMainThread)
  }

  func testBatchPreservesInputOrderAndIndividualFailure() async throws {
    let recorder = ProgressRecorder()
    let inputs: [DocumentInput] = [
      .data(Data("first".utf8), fileName: "first.txt"),
      .data(Data([0, 1, 2, 3, 4]), fileName: "unknown.bin"),
      .data(Data("third".utf8), fileName: "third.txt")
    ]
    let results = try await DocumentParser.parseBatch(
      inputs,
      options: DocumentParserOptions(maximumConcurrentDocuments: 2)
    ) { recorder.append($0) }
    XCTAssertEqual(results.count, 3)
    guard case .success(let first) = results[0],
      case .failure(let second) = results[1],
      case .success(let third) = results[2]
    else {
      return XCTFail("Batch results did not preserve each input outcome.")
    }
    XCTAssertEqual(first.fullText, "first")
    XCTAssertEqual(second, .unsupportedFormat)
    XCTAssertEqual(third.fullText, "third")
    let terminalEvents = recorder.events.filter {
      [.completed, .failed, .cancelled].contains($0.phase)
    }.sorted { $0.inputIndex < $1.inputIndex }
    XCTAssertEqual(terminalEvents.map(\.inputIndex), [0, 1, 2])
    XCTAssertEqual(terminalEvents.map(\.phase), [.completed, .failed, .completed])
  }

  func testCancellationAtExtractionPropagatesAndReportsTerminalEvent() async {
    let recorder = ProgressRecorder()
    let operation = Task {
      let input = DocumentInput.data(Data("Stopped".utf8), fileName: "cancel.txt")
      return try await DocumentParser.parse(input) { event in
        recorder.append(event)
        if event.phase == .extracting {
          withUnsafeCurrentTask { $0?.cancel() }
        }
      }
    }
    do {
      _ = try await operation.value
      XCTFail("Cancelled parsing completed successfully.")
    } catch {
      XCTAssertEqual(error as? DocumentParsingError, .cancelled)
    }
    XCTAssertEqual(recorder.events.last?.phase, .cancelled)
    XCTAssertFalse(recorder.events.contains { $0.phase == .completed })
  }

  func testMutatedZeroConcurrencyStillPreservesBatchResults() async throws {
    var options = DocumentParserOptions()
    options.maximumConcurrentDocuments = 0
    let results = try await DocumentParser.parseBatch(
      [.data(Data("Kept".utf8), fileName: "input.txt")], options: options
    )
    XCTAssertEqual(results.count, 1)
    guard let first = results.first, case .success(let result) = first else {
      return XCTFail("Batch dropped its input result.")
    }
    XCTAssertEqual(result.fullText, "Kept")
  }
}

nonisolated private final class ProgressRecorder: Sendable {
  private let storage = Mutex<[DocumentProgress]>([])

  var events: [DocumentProgress] {
    storage.withLock { $0 }
  }

  func append(_ event: DocumentProgress) {
    storage.withLock { $0.append(event) }
  }
}
