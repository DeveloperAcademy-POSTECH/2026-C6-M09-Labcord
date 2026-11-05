import ComposableArchitecture
import Foundation
import LabcordShared
import LabcordWatchOS
@testable import WatchScreens
import XCTest

@MainActor
final class WatchIntentRuntimeTests: XCTestCase {
    func testPhoneSessionArrivingBeforeListResponseIsReevaluated() async {
        let date = Date(timeIntervalSince1970: 1000)
        let streamID = UUID()
        let experimentID = UUID()
        let requestID = UUID()
        let summary = WatchExperimentSummary(id: experimentID, title: "A", status: .running)
        let snapshot = WatchExperimentSnapshot(
            experiment: summary, revision: 1, recordedAt: date, phoneSessionActive: true
        )
        var state = WatchExperimentFeature.State()
        state.isVisible = true
        state.streamID = streamID
        state.hasRestoredPending = true
        state.pending = .init(
            command: .init(requestID: requestID, operation: .list), responseID: requestID
        )
        let store = TestStore(initialState: state) { WatchExperimentFeature() } withDependencies: {
            $0.date.now = date
        }
        store.exhaustivity = .off
        await store.send(.snapshotReceived(streamID, snapshot))
        XCTAssertNil(store.state.selectedID)
        await store.send(.response(requestID, .init(
            requestID: requestID, phase: .completed, experiments: [summary]
        )))
        XCTAssertEqual(store.state.selectedID, experimentID)
        XCTAssertEqual(store.state.screen, .experiment)
        XCTAssertEqual(store.state.snapshot, snapshot)
        XCTAssertNil(store.state.deferredPhoneSession)
        await store.finish()
    }
    func testPhoneSessionFollowsOnlyFreshExplicitRunningSnapshot() async {
        let date = Date(timeIntervalSince1970: 1000)
        let streamID = UUID()
        let experimentID = UUID()
        var state = WatchExperimentFeature.State()
        state.isVisible = true
        state.streamID = streamID
        state.hasRestoredPending = true
        let store = TestStore(initialState: state) { WatchExperimentFeature() } withDependencies: {
            $0.date.now = date
        }
        store.exhaustivity = .off
        func snapshot(_ flag: Bool?, _ offset: TimeInterval, _ status: ExperimentStatus = .running)
            -> WatchExperimentSnapshot {
            .init(experiment: .init(id: experimentID, title: "A", status: status),
                  revision: 1, recordedAt: date.addingTimeInterval(offset),
                  phoneSessionActive: flag)
        }
        for value in [snapshot(nil, 0), snapshot(false, 0), snapshot(true, -31),
                      snapshot(true, 31), snapshot(true, 0, .paused)] {
            await store.send(.snapshotReceived(streamID, value))
            XCTAssertNil(store.state.selectedID)
            XCTAssertEqual(store.state.screen, .selection)
        }
        await store.send(.snapshotReceived(streamID, snapshot(true, -30)))
        XCTAssertEqual(store.state.selectedID, experimentID)
        XCTAssertEqual(store.state.screen, .experiment)
        XCTAssertEqual(store.state.snapshot?.experiment.status, .running)
        await store.finish()
    }

    func testPhoneSessionDoesNotDisplaceOtherExperimentOrUnsettledRecord() async {
        let date = Date(timeIntervalSince1970: 1000)
        let streamID = UUID()
        let experimentID = UUID()
        let snapshot = WatchExperimentSnapshot(
            experiment: .init(id: experimentID, title: "A", status: .running),
            revision: 1, recordedAt: date, phoneSessionActive: true
        )
        var state = WatchExperimentFeature.State()
        state.isVisible = true
        state.streamID = streamID
        state.hasRestoredPending = true
        let otherID = UUID()
        state.selectedID = otherID
        state.screen = .experiment
        let store = TestStore(initialState: state) { WatchExperimentFeature() } withDependencies: {
            $0.date.now = date
        }
        store.exhaustivity = .off
        await store.send(.snapshotReceived(streamID, snapshot))
        XCTAssertEqual(store.state.selectedID, otherID)
        XCTAssertEqual(store.state.screen, .experiment)
        XCTAssertNotNil(store.state.message)
        await store.finish()

        state.selectedID = nil
        state.screen = .selection
        let recordID = UUID()
        state.recording.records[recordID] = WatchRecordPresentation(
            id: recordID, experimentID: otherID, kind: .voice
        )
        let blocked = TestStore(initialState: state) {
            WatchExperimentFeature()
        } withDependencies: {
            $0.date.now = date
        }
        blocked.exhaustivity = .off
        await blocked.send(.snapshotReceived(streamID, snapshot))
        XCTAssertNil(blocked.state.selectedID)
        XCTAssertEqual(blocked.state.screen, .selection)
        await blocked.finish()
    }
    func testRemoteVoiceExpiresWhileWaitingForMicrophonePermission() async {
        let id = UUID()
        let expiry = Date.now.addingTimeInterval(0.05)
        var state = WatchExperimentFeature.State()
        state.isVisible = true
        state.streamID = UUID()
        state.selectedID = id
        state.screen = .experiment
        state.hasRestoredPending = true
        state.recording.isIntegrated = true
        state.snapshots[id] = WatchExperimentSnapshot(
            experiment: .init(id: id, title: "A", status: .running), revision: 1
        )
        let store = TestStore(initialState: state) { WatchExperimentFeature() } withDependencies: {
            $0.watchMicrophonePermission.request = {
                try? await Task.sleep(for: .milliseconds(100))
                return true
            }
        }
        store.exhaustivity = .off
        await store.send(.remoteVoiceRequested(id, expiry))
        await store.receive(.remoteVoicePermissionResult(id, expiry, true))
        XCTAssertTrue(store.state.recording.records.isEmpty)
        XCTAssertFalse(store.state.isRequestingPermission)
        await store.finish()
    }

    func testRemoteVoiceExpiresDuringRefreshBeforeRecordingStarts() async throws {
        let id = UUID()
        let snapshot = WatchExperimentSnapshot(
            experiment: .init(id: id, title: "A", status: .running), revision: 1
        )
        var state = WatchExperimentFeature.State()
        state.isVisible = true
        state.streamID = UUID()
        state.selectedID = id
        state.screen = .experiment
        state.isReachable = true
        state.hasRestoredPending = true
        state.recording.isIntegrated = true
        state.snapshots[id] = snapshot
        let store = Store(initialState: state) { WatchExperimentFeature() } withDependencies: {
            $0.uuid = .incrementing
            $0.continuousClock = TestClock()
            $0.date.now = Date(timeIntervalSince1970: 1)
            $0.watchExperimentClient.send = { command in
                try await Task.sleep(for: .seconds(1))
                return .init(requestID: command.requestID, phase: .completed, snapshot: snapshot)
            }
        }
        let runtime = WatchIntentRuntime(
            store: store, isActive: { true }, microphoneAllowed: { true }
        )
        do {
            _ = try await runtime.performRemoteVoice(
                experimentID: id, expiresAt: Date.now.addingTimeInterval(0.1)
            )
            XCTFail("상태 조회 중 만료된 요청이 수락됐습니다.")
        } catch let error as WatchIntentRuntimeError {
            guard case .requestRejected = error else { return XCTFail("예상과 다른 오류: \(error)") }
        }
        XCTAssertTrue(store.recording.records.isEmpty)
    }

    func testRemoteVoiceRejectsExpiredOrWrongExperimentWithoutRecording() async throws {
        let id = UUID()
        var state = WatchExperimentFeature.State()
        state.isVisible = true
        state.streamID = UUID()
        state.selectedID = id
        state.screen = .experiment
        state.snapshots[id] = WatchExperimentSnapshot(
            experiment: .init(id: id, title: "A", status: .running), revision: 1
        )
        let store = Store(initialState: state) { WatchExperimentFeature() }
        let runtime = WatchIntentRuntime(
            store: store, isActive: { true }, microphoneAllowed: { true }
        )
        do {
            _ = try await runtime.performRemoteVoice(experimentID: id, expiresAt: .distantPast)
            XCTFail("만료된 요청이 수락됐습니다.")
        } catch let error as WatchIntentRuntimeError {
            guard case .requestRejected = error else { return XCTFail("예상과 다른 오류: \(error)") }
        }
        do {
            _ = try await runtime.performRemoteVoice(
                experimentID: UUID(), expiresAt: .distantFuture
            )
            XCTFail("다른 실험의 요청이 수락됐습니다.")
        } catch let error as WatchIntentRuntimeError {
            XCTAssertEqual(error, .contextChanged)
        }
        XCTAssertTrue(store.recording.records.isEmpty)
    }

    func testPhotoIntentWaitsForPhoneRejectionInsteadOfLocalStarting() async throws {
        let id = UUID()
        let snapshot = WatchExperimentSnapshot(
            experiment: .init(id: id, title: "A", status: .running), revision: 1
        )
        var state = WatchExperimentFeature.State()
        state.isVisible = true
        state.streamID = UUID()
        state.isReachable = true
        state.hasRestoredPending = true
        state.recording.isIntegrated = true
        state.screen = .experiment
        state.selectedID = id
        state.snapshots = [id: snapshot]
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let journal = WatchPendingRequestJournal(url: url)
        let store = Store(initialState: state) {
            WatchExperimentFeature(pendingJournal: journal)
        } withDependencies: {
            $0.uuid = .incrementing
            $0.continuousClock = TestClock()
            $0.date.now = Date(timeIntervalSince1970: 1)
            $0.watchExperimentClient.send = { command in
                switch command.operation {
                case .snapshot:
                    return .init(
                        requestID: command.requestID, phase: .completed, snapshot: snapshot
                    )
                case .prepareStart:
                    return .init(
                        requestID: command.requestID, phase: .completed, startToken: UUID()
                    )
                case .takePhoto:
                    try await Task.sleep(for: .milliseconds(150))
                    return .init(
                        requestID: command.requestID, phase: .failed, error: .cameraUnavailable
                    )
                default:
                    throw WatchExperimentError.invalidState
                }
            }
        }
        let runtime = WatchIntentRuntime(
            store: store, isActive: { true }, microphoneAllowed: { true }
        )
        do {
            _ = try await runtime.perform(.photo)
            XCTFail("iPhone 촬영 거절을 받기 전에 성공을 반환했습니다.")
        } catch let error as WatchIntentRuntimeError {
            guard case .requestRejected = error else { return XCTFail("예상과 다른 오류: \(error)") }
        }
    }

}

extension WatchIntentRuntimeTests {
    func testDefinitivePhotoRejectionDoesNotBlockNextGesture() async throws {
        let experimentID = UUID()
        let recordID = UUID()
        let command = WatchExperimentCommand(
            operation: .takePhoto, experimentID: experimentID, targetID: recordID
        )
        let journal = WatchPendingRequestJournal(
            url: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        )
        try journal.save(command)
        var state = WatchExperimentFeature.State()
        state.isVisible = true
        state.streamID = UUID()
        state.hasRestoredPending = true
        state.screen = .experiment
        state.selectedID = experimentID
        state.recording.isIntegrated = true
        state.snapshots[experimentID] = .init(
            experiment: .init(id: experimentID, title: "A", status: .running), revision: 1
        )
        state.pending = .init(command: command, responseID: command.requestID)
        state.recording.records[recordID] = .init(
            id: recordID, experimentID: experimentID, kind: .photo
        )
        let store = TestStore(initialState: state) {
            WatchExperimentFeature(pendingJournal: journal)
        }
        store.exhaustivity = .off
        await store.send(.response(command.requestID, .init(
            requestID: command.requestID, phase: .failed, error: .phoneBusy
        )))
        await store.receive(.recording(.captureRejected(
            recordID, WatchExperimentError.phoneBusy.watchMessage
        )))
        XCTAssertNil(store.state.pending)
        XCTAssertEqual(store.state.recording.records[recordID]?.canRecapture, true)
        XCTAssertEqual(try WatchIntentRouting.action(for: .video, state: store.state),
                       .recordTapped(.video))
        XCTAssertNil(try journal.load())
        await store.finish()
    }

    func testUnknownPhotoOutcomeKeepsPendingAndBlocksNextGesture() async throws {
        let experimentID = UUID()
        let recordID = UUID()
        let command = WatchExperimentCommand(
            operation: .takePhoto, experimentID: experimentID, targetID: recordID
        )
        let journal = WatchPendingRequestJournal(
            url: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        )
        try journal.save(command)
        var state = WatchExperimentFeature.State()
        state.isVisible = true
        state.streamID = UUID()
        state.hasRestoredPending = true
        state.screen = .experiment
        state.selectedID = experimentID
        state.recording.isIntegrated = true
        state.snapshots[experimentID] = .init(
            experiment: .init(id: experimentID, title: "A", status: .running), revision: 1
        )
        state.pending = .init(command: command, responseID: command.requestID)
        state.recording.records[recordID] = .init(
            id: recordID, experimentID: experimentID, kind: .photo
        )
        let store = TestStore(initialState: state) {
            WatchExperimentFeature(pendingJournal: journal)
        }
        store.exhaustivity = .off
        await store.send(.response(command.requestID, .init(
            requestID: command.requestID, phase: .unknown
        )))
        XCTAssertEqual(store.state.pending?.phase, .uncertain)
        XCTAssertEqual(try journal.load(), command)
        XCTAssertThrowsError(try WatchIntentRouting.action(for: .video, state: store.state)) {
            XCTAssertEqual($0 as? WatchIntentRuntimeError, .busy)
        }
        await store.finish()
    }

}
