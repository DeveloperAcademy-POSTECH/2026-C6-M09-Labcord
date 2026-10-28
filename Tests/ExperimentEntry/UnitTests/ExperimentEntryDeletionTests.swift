import ComposableArchitecture
import Foundation
import LabcordShared
import SwiftData
import XCTest

@testable import EntryQA

@MainActor
final class ExperimentEntryDeletionTests: XCTestCase {
    private let identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let date = Date(timeIntervalSince1970: 1_791_892_800)

    func testDeleteRequestAndCancellationDoNotTouchStorage() async {
        let probe = DeleteProbe()
        let entry = row()
        let store = TestStore(initialState: ExperimentEntryFeature.State(entries: [entry])) {
            ExperimentEntryFeature()
        } withDependencies: {
            $0.experimentEntryClient.delete = { probe.identifiers.append($0) }
        }
        await store.send(.deleteRequested(identifier)) { $0.pendingDeletion = entry }
        await store.send(.deleteCancelled) { $0.pendingDeletion = nil }
        await store.send(.deleteRequested(UUID()))
        XCTAssertTrue(probe.identifiers.isEmpty)
        XCTAssertEqual(store.state.entries, [entry])
    }

    func testDeleteFailureKeepsRowAndRetryDeletesOnlySelectedUUID() async {
        let probe = DeleteProbe()
        let entry = row()
        let other = ExperimentListEntry(
            id: UUID(), title: "남길 실험", createdAt: date, status: .inProgress
        )
        let initialState = ExperimentEntryFeature.State(entries: [entry, other])
        let store = TestStore(initialState: initialState) {
            ExperimentEntryFeature()
        } withDependencies: {
            $0.experimentEntryClient.delete = { id in
                probe.identifiers.append(id)
                if probe.identifiers.count == 1 {
                    throw ExperimentEntryFeature.Failure.deleting
                }
            }
        }
        await store.send(.deleteRequested(identifier)) { $0.pendingDeletion = entry }
        // SwiftUI가 확인 액션 전에 경고창 binding을 닫아도 선택한 UUID를 삭제합니다.
        await store.send(.deleteCancelled) { $0.pendingDeletion = nil }
        await store.send(.deleteConfirmed(identifier)) {
            $0.isDeleting = true
            $0.deletionID = self.identifier
            $0.loadRevision = 1
        }
        await store.receive(.deleteFailed(identifier)) {
            $0.isDeleting = false
            $0.failure = .deleting
        }
        XCTAssertEqual(store.state.entries, [entry, other])
        await store.send(.dismissFailure) { $0.failure = nil }
        await store.send(.retryTapped(.deleting)) {
            $0.isDeleting = true
            $0.loadRevision = 2
        }
        await store.receive(.deleteSucceeded(identifier)) {
            $0.isDeleting = false
            $0.deletionID = nil
            $0.entries = [other]
        }
        await store.send(.loaded(1, .success([entry, other])))
        await store.send(.deleteConfirmed(identifier))
        XCTAssertEqual(probe.identifiers, [identifier, identifier])
    }

    func testDeletionBlocksDuplicateRequestsAndNavigation() async {
        let entry = row()
        let store = TestStore(initialState: ExperimentEntryFeature.State(
            entries: [entry], isDeleting: true, deletionID: identifier, loadRevision: 2
        )) {
            ExperimentEntryFeature()
        }
        await store.send(.deleteRequested(identifier))
        await store.send(.deleteConfirmed(identifier))
        await store.send(.load)
        await store.send(.addTapped)
        await store.send(.experimentTapped(identifier))
        await store.send(.editTapped(identifier))
        await store.send(.loaded(1, .success([])))
        await store.send(.deleteSucceeded(UUID()))
        await store.send(.deleteFailed(UUID()))
    }

    func testEditPassesExistingUUIDWithoutCreatingExperiment() async {
        let entry = row()
        let store = TestStore(initialState: ExperimentEntryFeature.State(entries: [entry])) {
            ExperimentEntryFeature()
        }
        await store.send(.editTapped(identifier))
        await store.receive(.delegate(.protocolEditRequested(identifier)))
        await store.send(.editTapped(UUID()))
    }

    func testRepositoryDeleteCascadesAndPreservesOtherExperiment() throws {
        let container = try memoryContainer()
        let context = ModelContext(container)
        let record = ExperimentRecord(
            id: UUID(), type: .timer, recordedAt: date, note: "삭제 대상",
            timerPauses: [Pause(pausedAt: date)]
        )
        context.insert(Experiment(
            id: identifier, title: "삭제 대상", createdAt: date,
            pauses: [Pause(pausedAt: date)], records: [record]
        ))
        let retainedID = UUID()
        context.insert(Experiment(id: retainedID, title: "남길 실험", createdAt: date))
        try context.save()
        let repository = ExperimentEntryRepository { container }
        try repository.delete(id: identifier)
        try repository.delete(id: identifier)
        let inspection = ModelContext(container)
        XCTAssertEqual(try repository.load().map(\.id), [retainedID])
        XCTAssertEqual(try inspection.fetchCount(FetchDescriptor<ExperimentRecord>()), 0)
        XCTAssertEqual(try inspection.fetchCount(FetchDescriptor<Pause>()), 0)
        XCTAssertEqual(try inspection.fetchCount(FetchDescriptor<ExperimentStatusEntry>()), 1)
    }

    func testDiskDeletionSurvivesReopening() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema([
            Experiment.self, ExperimentRecord.self, Pause.self, ExperimentStatusEntry.self
        ])
        let configuration = ModelConfiguration(
            schema: schema, url: directory.appending(path: "delete.store")
        )
        let makeContainer = { try ModelContainer(for: schema, configurations: configuration) }
        let repository = ExperimentEntryRepository(makeContainer: makeContainer)
        _ = try repository.create(id: identifier, at: date)
        try repository.delete(id: identifier)
        XCTAssertTrue(try ExperimentEntryRepository(makeContainer: makeContainer).load().isEmpty)
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
private final class DeleteProbe {
    var identifiers: [UUID] = []
}
