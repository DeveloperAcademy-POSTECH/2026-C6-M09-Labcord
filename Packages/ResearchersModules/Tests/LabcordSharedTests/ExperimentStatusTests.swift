import LabcordShared
import XCTest

final class ExperimentStatusTests: XCTestCase {
    func testRecordEntryRunsOnlyFromReadyOrPaused() {
        let experiment = Experiment(title: "실험", status: .ready)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        experiment.recordEntry(at: start)

        XCTAssertEqual(experiment.status, .running)
        XCTAssertEqual(runningEntries(in: experiment).count, 1)

        experiment.recordEntry(at: start.addingTimeInterval(10))
        XCTAssertEqual(runningEntries(in: experiment).count, 1)

        experiment.complete(at: start.addingTimeInterval(20))
        experiment.recordEntry(at: start.addingTimeInterval(30))
        XCTAssertEqual(experiment.status, .completed)
        XCTAssertEqual(runningEntries(in: experiment).count, 1)
    }

    func testRecordExitIsIdempotent() {
        let experiment = Experiment(title: "실험", status: .paused)
        let exitID = UUID()
        let pausedAt = Date(timeIntervalSince1970: 20)
        experiment.recordExit(at: pausedAt, entryID: exitID)
        experiment.recordExit(at: pausedAt.addingTimeInterval(5), entryID: exitID)

        XCTAssertEqual(experiment.status, .paused)
        XCTAssertEqual(experiment.statusHistory.filter { $0.id == exitID }.count, 1)
    }

    func testRepairInterruptedRunPausesAtLastHistoryDate() {
        let createdAt = Date(timeIntervalSince1970: 1)
        let experiment = Experiment(title: "실험", createdAt: createdAt, status: .ready)
        let runningAt = Date(timeIntervalSince1970: 50)
        experiment.recordEntry(at: runningAt)
        let exitID = UUID()

        experiment.repairInterruptedRun(entryID: exitID)

        XCTAssertEqual(experiment.status, .paused)
        XCTAssertEqual(experiment.statusHistory.first { $0.id == exitID }?.date, runningAt)

        experiment.repairInterruptedRun(entryID: UUID())
        XCTAssertEqual(experiment.statusHistory.filter { $0.status == .paused }.count, 1)
    }

    func testRepairIgnoresExperimentThatIsNotRunning() {
        let experiment = Experiment(title: "실험", status: .ready)
        experiment.repairInterruptedRun(entryID: UUID())
        XCTAssertEqual(experiment.status, .ready)
    }

    private func runningEntries(in experiment: Experiment) -> [ExperimentStatusEntry] {
        experiment.statusHistory.filter { $0.status == .running }
    }
}
