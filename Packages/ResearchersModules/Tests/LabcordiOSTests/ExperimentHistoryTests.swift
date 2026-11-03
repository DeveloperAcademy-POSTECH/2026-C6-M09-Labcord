import Foundation
@testable import LabcordiOS
import LabcordShared
import XCTest

final class ExperimentHistoryTests: XCTestCase {
    @MainActor
    func testReadingCompletedHistoryPreservesStatusAndStoredProtocol() throws {
        let client = ExperimentClient.liveValue
        let id = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        let endedAt = createdAt.addingTimeInterval(60)
        let procedure = ExperimentProtocol(timerSeconds: [15, 754, 3_661])
        _ = try client.createWithProtocol(id, createdAt, "기록 조회 QA", procedure)
        defer { try? client.delete(id) }
        _ = try client.loadDetail(id)
        try client.complete(id, endedAt)

        let before = try XCTUnwrap(client.loadResultDetail(id))
        let after = try XCTUnwrap(client.loadResultDetail(id))
        XCTAssertEqual(after, before)
        XCTAssertEqual(after.status, .completed)
        XCTAssertEqual(after.endedAt, [endedAt])
        XCTAssertEqual(after.procedure?.timerSeconds, [15, 754, 3_661])
    }

    @MainActor
    func testExplicitSessionResumeKeepsPriorCompletionAndDoesNotDuplicateEntry() throws {
        let client = ExperimentClient.liveValue
        let id = UUID()
        let endedAt = Date.now.addingTimeInterval(-60)
        _ = try client.create(id, endedAt.addingTimeInterval(-60))
        defer { try? client.delete(id) }
        try client.complete(id, endedAt)
        let completed = try XCTUnwrap(client.loadResultDetail(id))

        _ = try XCTUnwrap(client.loadDetail(id))
        let resumed = try XCTUnwrap(client.loadResultDetail(id))
        XCTAssertEqual(resumed.status, .running)
        XCTAssertEqual(resumed.endedAt, completed.endedAt)
        XCTAssertEqual(resumed.records, completed.records)
        XCTAssertEqual(resumed.statusHistory.count, completed.statusHistory.count + 1)
        XCTAssertEqual(resumed.statusHistory.last?.status, .running)

        _ = try client.loadDetail(id)
        XCTAssertEqual(try client.loadResultDetail(id)?.statusHistory, resumed.statusHistory)
    }
}
