import ComposableArchitecture
import Foundation
import LabcordShared
import LabcordWatchOS
@testable import WatchScreens
import XCTest

@MainActor
final class WatchRecordAutoSaveTests: XCTestCase {
    private func review(_ id: UUID, experimentID: UUID) -> WatchRecordPresentation {
        var record = WatchRecordPresentation(id: id, experimentID: experimentID, kind: .photo)
        record.revision = 1
        record.phase = .review
        record.canAutoSave = true
        return record
    }

    func testSameRevisionRestartsCountdownAfterInterruption() async {
        let clock = TestClock()
        let id = UUID()
        let record = review(id, experimentID: UUID())
        var state = WatchRecordFeature.State()
        state.isIntegrated = true
        let store = TestStore(initialState: state) { WatchRecordFeature() } withDependencies: {
            $0.continuousClock = clock
        }
        store.exhaustivity = .off
        await store.send(.update(record))
        XCTAssertEqual(store.state.autoSaveSeconds[id], 3)
        await store.send(.interrupted)
        XCTAssertNil(store.state.autoSaveSeconds[id])
        await store.send(.update(record))
        XCTAssertEqual(store.state.autoSaveSeconds[id], 3)
        await store.send(.autoSaveTick(id, 1))
        XCTAssertEqual(store.state.autoSaveSeconds[id], 2)
        await store.send(.interrupted)
        await store.finish()
    }

    func testNewRevisionKeepsRemainingCountdownAndRejectsStaleTick() async {
        let clock = TestClock()
        let id = UUID()
        var record = review(id, experimentID: UUID())
        var state = WatchRecordFeature.State()
        state.isIntegrated = true
        let store = TestStore(initialState: state) { WatchRecordFeature() } withDependencies: {
            $0.continuousClock = clock
        }
        store.exhaustivity = .off
        await store.send(.update(record))
        await store.send(.autoSaveTick(id, 1))
        XCTAssertEqual(store.state.autoSaveSeconds[id], 2)
        record.revision = 2
        await store.send(.update(record))
        XCTAssertEqual(store.state.autoSaveSeconds[id], 2)
        await store.send(.autoSaveTick(id, 1))
        XCTAssertEqual(store.state.autoSaveSeconds[id], 2)
        await store.send(.autoSaveTick(id, 2))
        XCTAssertEqual(store.state.autoSaveSeconds[id], 1)
        await store.send(.autoSaveTick(id, 2))
        XCTAssertEqual(store.state.decisions[id], .save)
        XCTAssertEqual(store.state.records[id]?.phase, .saving)
        await store.receive(.delegate(.command(
            .confirmRecord, recordID: id, experimentID: record.experimentID
        )))
        await store.finish()
    }

    func testRecoveredCountdownFiresOnClockAndRequestsSave() async {
        let clock = TestClock()
        let id = UUID()
        let record = review(id, experimentID: UUID())
        var state = WatchRecordFeature.State()
        state.isIntegrated = true
        let store = TestStore(initialState: state) { WatchRecordFeature() } withDependencies: {
            $0.continuousClock = clock
        }
        store.exhaustivity = .off
        await store.send(.update(record))
        await store.send(.interrupted)
        await store.send(.update(record))
        for _ in 0..<3 {
            await clock.advance(by: .seconds(1))
            await store.receive(.autoSaveTick(id, 1))
        }
        await store.receive(.delegate(.command(
            .confirmRecord, recordID: id, experimentID: record.experimentID
        )))
        XCTAssertEqual(store.state.decisions[id], .save)
        await store.finish()
    }

    func testCancellationBlocksSameAndNewerReviewUpdates() async {
        let clock = TestClock()
        let id = UUID()
        var record = review(id, experimentID: UUID())
        var state = WatchRecordFeature.State()
        state.isIntegrated = true
        let store = TestStore(initialState: state) { WatchRecordFeature() } withDependencies: {
            $0.continuousClock = clock
        }
        store.exhaustivity = .off
        await store.send(.update(record))
        await store.send(.cancel(id))
        await store.receive(.delegate(.command(
            .cancelRecord, recordID: id, experimentID: record.experimentID
        )))
        await store.send(.update(record))
        record.revision = 2
        await store.send(.update(record))
        await store.send(.autoSaveTick(id, 2))
        XCTAssertEqual(store.state.decisions[id], .cancel)
        XCTAssertEqual(store.state.records[id]?.phase, .saving)
        XCTAssertNil(store.state.autoSaveSeconds[id])
        await store.finish()
    }

    func testChangedPayloadWithSameRevisionDoesNotRestartCountdown() async {
        let clock = TestClock()
        let id = UUID()
        var record = review(id, experimentID: UUID())
        var state = WatchRecordFeature.State()
        state.isIntegrated = true
        let store = TestStore(initialState: state) { WatchRecordFeature() } withDependencies: {
            $0.continuousClock = clock
        }
        store.exhaustivity = .off
        await store.send(.update(record))
        await store.send(.interrupted)
        record.detail = "different payload"
        await store.send(.update(record))
        XCTAssertNil(store.state.autoSaveSeconds[id])
        XCTAssertNil(store.state.records[id]?.detail)
        await store.finish()
    }

    func testVoiceShortcutStopsOnlySelectedExperimentsRecording() {
        let selectedID = UUID()
        let otherID = UUID()
        var other = WatchRecordPresentation(id: UUID(), experimentID: otherID, kind: .voice)
        other.phase = .capturing
        var state = WatchExperimentFeature.State()
        state.screen = .experiment
        state.selectedID = selectedID
        state.recording.records[other.id] = other
        XCTAssertNil(WatchIntentRouting.localVoiceStop(state: state))

        var selected = WatchRecordPresentation(
            id: UUID(), experimentID: selectedID, kind: .voice
        )
        selected.phase = .capturing
        state.recording.records[selected.id] = selected
        XCTAssertEqual(WatchIntentRouting.localVoiceStop(state: state),
                       .recording(.stop(selected.id)))
        state.selectedID = nil
        XCTAssertNil(WatchIntentRouting.localVoiceStop(state: state))
    }

    func testBufferedReviewStartsCountdownAfterObserverActivation() async {
        let clock = TestClock()
        let streamID = UUID()
        let record = review(UUID(), experimentID: UUID())
        var state = WatchExperimentFeature.State()
        state.isVisible = true
        state.streamID = streamID
        let bridge = WatchRecordingUIBridge(
            perform: { _ in },
            updates: { AsyncStream { $0.yield(record) } }
        )
        let store = TestStore(initialState: state) {
            WatchExperimentFeature(recordingBridge: bridge)
        } withDependencies: {
            $0.continuousClock = clock
        }
        store.exhaustivity = .off
        await store.send(.recordReconnect)
        await store.receive(.recording(.integrationAvailable(true)))
        await store.receive(.recording(.delegate(.local(.reconcile))))
        await store.receive(.recordUpdate(streamID, record))
        await store.receive(.recording(.update(record)))
        XCTAssertEqual(store.state.recording.autoSaveSeconds[record.id], 3)
        await store.send(.inactive)
        await store.finish()
    }

    func testStatusQueryTimeoutReturnsProcessingRequestToUncertain() async throws {
        let clock = TestClock()
        let originalID = UUID()
        let command = WatchExperimentCommand(
            requestID: originalID, operation: .takePhoto, experimentID: UUID()
        )
        var state = WatchExperimentFeature.State()
        state.isVisible = true
        state.streamID = UUID()
        state.isReachable = true
        state.pending = .init(command: command, responseID: originalID, phase: .processing)
        let store = TestStore(initialState: state) { WatchExperimentFeature() } withDependencies: {
            $0.continuousClock = clock
            $0.uuid = .incrementing
            $0.watchExperimentClient.send = { _ in
                try await Task.sleep(for: .seconds(600))
                throw WatchExperimentError.resultUnknown
            }
        }
        store.exhaustivity = .off
        await store.send(.checkRequest)
        let queryID = try XCTUnwrap(store.state.pending?.responseID)
        XCTAssertNotEqual(queryID, originalID)
        XCTAssertEqual(store.state.pending?.phase, .delivering)
        await clock.advance(by: .seconds(3))
        await store.receive(.deliveryExpired(queryID))
        XCTAssertEqual(store.state.pending?.phase, .uncertain)
        XCTAssertEqual(store.state.pending?.command.requestID, originalID)
        await store.send(.inactive)
        await store.finish()
    }

    func testShortcutIgnoresOtherExperimentsInactiveRecordsOnly() throws {
        let selectedID = UUID()
        var state = WatchExperimentFeature.State()
        state.isVisible = true
        state.streamID = UUID()
        state.hasRestoredPending = true
        state.screen = .experiment
        state.selectedID = selectedID
        state.recording.isIntegrated = true
        state.snapshots[selectedID] = WatchExperimentSnapshot(
            experiment: .init(id: selectedID, title: "A", status: .running), revision: 1
        )
        var other = WatchRecordPresentation(id: UUID(), experimentID: UUID(), kind: .photo)
        for phase in [WatchRecordPresentation.Phase.failed, .review] {
            other.phase = phase
            state.recording.records[other.id] = other
            XCTAssertEqual(try WatchIntentRouting.action(for: .photo, state: state),
                           .recordTapped(.photo))
        }
        for phase in [WatchRecordPresentation.Phase.starting, .capturing, .stopping] {
            other.phase = phase
            state.recording.records[other.id] = other
            XCTAssertThrowsError(try WatchIntentRouting.action(for: .photo, state: state)) {
                XCTAssertEqual($0 as? WatchIntentRuntimeError, .busy)
            }
        }
        state.recording.records.removeAll()
        var selected = WatchRecordPresentation(id: UUID(), experimentID: selectedID, kind: .photo)
        selected.phase = .failed
        state.recording.records[selected.id] = selected
        XCTAssertThrowsError(try WatchIntentRouting.action(for: .photo, state: state)) {
            XCTAssertEqual($0 as? WatchIntentRuntimeError, .busy)
        }
    }
}

extension WatchRecordAutoSaveTests {
    func testVoiceButtonRequestsPermissionBeforeStarting() async {
        let id = UUID()
        var state = WatchExperimentFeature.State()
        state.isVisible = true
        state.streamID = UUID()
        state.selectedID = id
        state.hasRestoredPending = true
        state.recording.isIntegrated = true
        state.snapshots[id] = WatchExperimentSnapshot(
            experiment: .init(id: id, title: "A", status: .running), revision: 1
        )
        let store = TestStore(initialState: state) { WatchExperimentFeature() } withDependencies: {
            $0.uuid = .incrementing
            $0.watchMicrophonePermission.request = { true }
        }
        store.exhaustivity = .off
        await store.send(.recordTapped(.voice))
        await store.receive(.voicePermissionResult(id, true))
        await store.receive(.recording(.begin(.voice, id)))
        XCTAssertEqual(store.state.recording.records.values.first?.kind, .voice)
        await store.finish()
    }

    func testVoiceButtonDeniedPermissionDoesNotStartRecording() async {
        let id = UUID()
        var state = WatchExperimentFeature.State()
        state.isVisible = true
        state.streamID = UUID()
        state.selectedID = id
        state.hasRestoredPending = true
        state.recording.isIntegrated = true
        state.snapshots[id] = WatchExperimentSnapshot(
            experiment: .init(id: id, title: "A", status: .running), revision: 1
        )
        let store = TestStore(initialState: state) { WatchExperimentFeature() } withDependencies: {
            $0.watchMicrophonePermission.request = { false }
        }
        store.exhaustivity = .off
        await store.send(.recordTapped(.voice))
        await store.receive(.voicePermissionResult(id, false))
        XCTAssertTrue(store.state.recording.records.isEmpty)
        XCTAssertNotNil(store.state.message)
        await store.finish()
    }
}

extension WatchRecordAutoSaveTests {
    func testEmptyVoiceCaptureRequiresNoEvidenceOfAudioOrActiveCapture() {
        let header = WatchAudioHeader(
            experimentID: UUID(), recordingID: UUID(), startedAt: .now, sampleRate: 16_000
        )
        let empty = WatchAudioReceipt(header: header, receivedSequences: [], manifest: nil)
        let chunk = WatchAudioReceipt(header: header, receivedSequences: [0], manifest: nil)
        let reviewing = WatchAudioReceipt(
            header: header, receivedSequences: [], manifest: nil, isReviewing: true
        )
        XCTAssertTrue(WatchRecordPresentation.isEmptyVoiceCapture(
            local: empty, remote: nil, hasActiveCapture: false
        ))
        XCTAssertTrue(WatchRecordPresentation.isEmptyVoiceCapture(
            local: empty, remote: empty, hasActiveCapture: false
        ))
        XCTAssertFalse(WatchRecordPresentation.isEmptyVoiceCapture(
            local: empty, remote: nil, hasActiveCapture: true
        ))
        XCTAssertFalse(WatchRecordPresentation.isEmptyVoiceCapture(
            local: chunk, remote: nil, hasActiveCapture: false
        ))
        XCTAssertFalse(WatchRecordPresentation.isEmptyVoiceCapture(
            local: empty, remote: reviewing, hasActiveCapture: false
        ))
    }

    func testLateRecoveryStillUpdatesEmptyRejectedVoice() async {
        let id = UUID()
        let experimentID = UUID()
        var empty = WatchRecordPresentation(id: id, experimentID: experimentID, kind: .voice)
        empty.phase = .failed
        empty.captureRejectedBeforeStart = true
        empty.revision = 1
        var state = WatchRecordFeature.State()
        state.isIntegrated = true
        let store = TestStore(initialState: state) { WatchRecordFeature() }
        store.exhaustivity = .off
        await store.send(.update(empty))
        XCTAssertTrue(store.state.records[id]?.canRecapture == true)

        var recovered = empty
        recovered.revision = 2
        recovered.phase = .transferring
        recovered.captureRejectedBeforeStart = false
        recovered.originalRetained = true
        await store.send(.update(recovered))
        XCTAssertEqual(store.state.records[id]?.phase, .transferring)
        XCTAssertTrue(store.state.records[id]?.originalRetained == true)
    }

}
