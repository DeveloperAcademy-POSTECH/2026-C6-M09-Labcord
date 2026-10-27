import ComposableArchitecture
import Foundation
import LabcordShared
import SwiftData
import XCTest

@testable import EntryQA

@MainActor
final class ExperimentEntryTests: XCTestCase {
    private let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let date = Date(timeIntervalSince1970: 1_791_892_800)

    func testRetryKeepsIdentityAndEmitsOnlyAfterSaving() async {
        let probe = SaveProbe()
        let entry = row()
        let store = TestStore(initialState: ExperimentEntryFeature.State(isRegistering: true)) {
            ExperimentEntryFeature()
        } withDependencies: {
            $0.uuid = .constant(identifier)
            $0.date = .constant(date)
            $0.experimentEntryClient = ExperimentEntryClient(load: { [entry] }, create: { id, _ in
                probe.identifiers.append(id)
                if probe.identifiers.count == 1 { throw ExperimentEntryFeature.Failure.saving }
                return entry
            })
        }

        await store.send(.skipTapped) {
            $0.pendingID = self.identifier
            $0.isSaving = true
            $0.loadRevision = 1
        }
        await store.receive(.saved(.failure(.saving))) {
            $0.isSaving = false
            $0.failure = .saving
        }
        // 경고창이 액션보다 먼저 닫혀도 재시도가 유효해야 합니다.
        await store.send(.dismissFailure) { $0.failure = nil }
        await store.send(.retryTapped(.saving))
        await store.receive(.skipTapped) {
            $0.isSaving = true
            $0.loadRevision = 2
        }
        await store.receive(.saved(.success(entry))) {
            $0.isSaving = false
            $0.entries = [entry]
            $0.isRegistering = false
            $0.pendingID = nil
        }
        await store.receive(.delegate(.experimentCreated(identifier)))
        await store.receive(.load) {
            $0.isLoading = true
            $0.loadRevision = 3
        }
        await store.receive(.loaded(3, .success([entry]))) { $0.isLoading = false }
        XCTAssertEqual(probe.identifiers, [identifier, identifier])
    }

    func testSavingBlocksDuplicateSubmissionAndBackNavigation() async {
        let probe = SaveProbe()
        let store = TestStore(initialState: ExperimentEntryFeature.State(
            isRegistering: true, isSaving: true, pendingID: identifier
        )) {
            ExperimentEntryFeature()
        } withDependencies: {
            $0.experimentEntryClient = ExperimentEntryClient(load: { [] }, create: { id, _ in
                probe.identifiers.append(id)
                throw ExperimentEntryFeature.Failure.saving
            })
        }
        await store.send(.skipTapped)
        await store.send(.registrationPresented(false))
        await store.send(.sourceTapped(.photos))
        XCTAssertTrue(probe.identifiers.isEmpty)
    }

    func testStaleLoadCannotOverwriteCreatedEntry() async {
        let entry = row()
        let store = TestStore(initialState: ExperimentEntryFeature.State(
            entries: [entry], loadRevision: 2
        )) {
            ExperimentEntryFeature()
        }
        await store.send(.loaded(1, .success([])))
        await store.send(.experimentTapped(identifier))
        await store.receive(.delegate(.experimentSelected(identifier)))
        await store.send(.experimentTapped(UUID()))
    }

    func testBackDiscardsDraftAndSourceSelectionDoesNotCreateExperiment() async {
        let store = TestStore(initialState: ExperimentEntryFeature.State()) {
            ExperimentEntryFeature()
        }
        await store.send(.addTapped) { $0.isRegistering = true }
        await store.send(.sourceTapped(.file))
        await store.receive(.delegate(.protocolSourceRequested(.file)))
        await store.send(.registrationPresented(false)) { $0.isRegistering = false }
        XCTAssertTrue(store.state.entries.isEmpty)
    }

    func testRepositoryCreatesPreparingExperimentAndDeduplicatesRetries() throws {
        let container = try memoryContainer()
        let repository = ExperimentEntryRepository { container }
        let entry = try repository.create(id: identifier, at: date)
        let retried = try repository.create(id: identifier, at: date.addingTimeInterval(60))
        XCTAssertEqual(retried, entry)
        XCTAssertEqual(try repository.load(), [entry])
        let models = try ModelContext(container).fetch(FetchDescriptor<Experiment>())
        XCTAssertEqual(models.count, 1)
        let experiment = try XCTUnwrap(models.first)
        XCTAssertEqual(experiment.title, "새 실험")
        XCTAssertEqual(experiment.status, .preparing)
        XCTAssertNil(experiment.procedure)
        XCTAssertNil(experiment.startedAt)
        XCTAssertTrue(experiment.records.isEmpty)
        XCTAssertEqual(experiment.statusHistory.count, 1)
        XCTAssertEqual(experiment.statusHistory.first?.status, .preparing)
    }

    func testDiskStoreRetainsUUIDWhenReopened() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema([
            Experiment.self, ExperimentRecord.self, Pause.self, ExperimentStatusEntry.self
        ])
        let configuration = ModelConfiguration(
            schema: schema, url: directory.appending(path: "test.store")
        )
        let makeContainer = { try ModelContainer(for: schema, configurations: configuration) }
        let repository = ExperimentEntryRepository(makeContainer: makeContainer)
        let original = try repository.create(id: identifier, at: date)
        let reopened = ExperimentEntryRepository(makeContainer: makeContainer)
        XCTAssertEqual(try reopened.load(), [original])
    }

    func testContainerInitializationFailureCanBeRetried() throws {
        let probe = SaveProbe()
        let repository = ExperimentEntryRepository {
            probe.initializationCount += 1
            if probe.initializationCount == 1 { throw ExperimentEntryFeature.Failure.loading }
            return try self.memoryContainer()
        }
        XCTAssertThrowsError(try repository.load())
        XCTAssertEqual(try repository.load(), [])
        XCTAssertEqual(probe.initializationCount, 2)
    }

    func testSortingAndGroupingUseStableIdentity() {
        let first = row()
        let later = ExperimentListEntry(
            id: UUID(), title: "나중 실험", createdAt: date.addingTimeInterval(60), status: .paused
        )
        XCTAssertEqual([first, later].sorted(by: ExperimentListEntry.newestFirst), [later, first])
        XCTAssertFalse(first.isActive)
        XCTAssertTrue(later.isActive)
    }

    private func row() -> ExperimentListEntry {
        ExperimentListEntry(id: identifier, title: "새 실험", createdAt: date, status: .preparing)
    }

    private func memoryContainer() throws -> ModelContainer {
        let schema = Schema([
            Experiment.self, ExperimentRecord.self, Pause.self, ExperimentStatusEntry.self
        ])
        return try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
    }
}

@MainActor
private final class SaveProbe {
    var identifiers: [UUID] = []
    var initializationCount = 0
}
