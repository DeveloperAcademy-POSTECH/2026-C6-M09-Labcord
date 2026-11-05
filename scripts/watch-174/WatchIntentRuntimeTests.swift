import ComposableArchitecture
import Foundation
import LabcordShared
import LabcordWatchOS
@testable import WatchScreens
import XCTest

@MainActor
final class WatchIntentRuntimeTests: XCTestCase {
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
