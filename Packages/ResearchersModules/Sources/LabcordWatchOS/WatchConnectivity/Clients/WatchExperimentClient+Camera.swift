import Foundation
import LabcordShared

public extension WatchExperimentClient {
    func pendingCameraRecord(experimentID: UUID, kind: WatchRecordSnapshot.Kind) -> UUID? {
        let key = pendingCameraKey(experimentID: experimentID, kind: kind)
        return UserDefaults.standard.string(forKey: key).flatMap(UUID.init(uuidString:))
    }

    func clearPendingCameraRecord(
        experimentID: UUID, kind: WatchRecordSnapshot.Kind, recordID: UUID
    ) {
        guard pendingCameraRecord(experimentID: experimentID, kind: kind) == recordID else {
            return
        }
        UserDefaults.standard.removeObject(forKey: pendingCameraKey(
            experimentID: experimentID, kind: kind
        ))
    }

    func cameraRecordUpdates(
        experimentID: UUID, recordID: UUID, kind: WatchRecordSnapshot.Kind
    ) -> AsyncStream<WatchExperimentResponse> {
        AsyncStream { continuation in
            let task = Task {
                defer { continuation.finish() }
                var lastRecord: WatchRecordSnapshot?
                var lastError: WatchExperimentError?
                let absenceDeadline = ContinuousClock.now.advanced(by: .seconds(4))
                while !Task.isCancelled {
                    if let result = try? await cameraCommandStatus(
                        experimentID: experimentID, requestID: recordID, kind: kind
                    ), result.record != lastRecord || result.error != lastError {
                        if result.phase == .unknown, result.error == .requestExpired,
                           ContinuousClock.now < absenceDeadline {
                            try? await Task.sleep(for: .seconds(1))
                            continue
                        }
                        lastRecord = result.record
                        lastError = result.error
                        continuation.yield(result)
                    }
                    try? await Task.sleep(for: .seconds(2))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func startCameraRecord(
        experimentID: UUID, recordID: UUID, kind: WatchRecordSnapshot.Kind
    ) async throws -> WatchExperimentResponse {
        let revision = try await cameraRevision(experimentID)
        let preparation = try await waitForCameraCommand(.init(
            operation: .prepareStart, experimentID: experimentID, expectedRevision: revision
        ))
        guard let token = preparation.startToken else {
            throw preparation.error ?? WatchExperimentError.requestExpired
        }
        try Task.checkCancellation()
        UserDefaults.standard.set(recordID.uuidString, forKey: pendingCameraKey(
            experimentID: experimentID, kind: kind
        ))
        return try await waitForCameraCommand(.init(
            requestID: recordID, operation: kind == .photo ? .takePhoto : .startVideo,
            experimentID: experimentID,
            expectedRevision: preparation.snapshot?.revision ?? revision,
            targetID: recordID, startToken: token, recordKind: kind
        ))
    }

    func finishCameraRecord(
        experimentID: UUID, recordID: UUID, kind: WatchRecordSnapshot.Kind,
        operation: WatchExperimentCommand.Operation
    ) async throws -> WatchExperimentResponse {
        let revision = try await cameraRevision(experimentID)
        return try await waitForCameraCommand(.init(
            operation: operation, experimentID: experimentID, expectedRevision: revision,
            targetID: recordID, recordKind: kind
        ))
    }

    private func cameraCommandStatus(
        experimentID: UUID?, requestID: UUID, kind: WatchRecordSnapshot.Kind?
    ) async throws -> WatchExperimentResponse {
        let response = try await send(.init(
            operation: .requestStatus, experimentID: experimentID, targetID: requestID,
            recordKind: kind
        ))
        guard response.queriedRequestID == requestID else {
            throw response.error ?? WatchExperimentError.invalidPayload
        }
        return response
    }

    private func pendingCameraKey(experimentID: UUID, kind: WatchRecordSnapshot.Kind) -> String {
        "watch.camera.pending.\(kind.rawValue).\(experimentID.uuidString)"
    }

    private func cameraRevision(_ experimentID: UUID) async throws -> UInt64 {
        let response = try await send(.init(operation: .snapshot, experimentID: experimentID))
        guard response.phase == .completed, let snapshot = response.snapshot else {
            throw response.error ?? WatchExperimentError.resultUnknown
        }
        return snapshot.revision
    }

    private func waitForCameraCommand(
        _ command: WatchExperimentCommand
    ) async throws -> WatchExperimentResponse {
        try Task.checkCancellation()
        let deadline = ContinuousClock.now.advanced(by: .seconds(12))
        do {
            let response = try await send(command)
            if isCameraReplyReady(response, for: command) { return response }
        } catch WatchExperimentError.notReachable {
            return .init(requestID: command.requestID, phase: .failed, error: .notReachable)
        } catch {
            try Task.checkCancellation()
        }

        while ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(300))
            if let response = try? await cameraCommandStatus(
                experimentID: command.experimentID, requestID: command.requestID,
                kind: command.recordKind
            ), isCameraReplyReady(response, for: command) {
                return response
            }
        }
        try Task.checkCancellation()
        return .init(requestID: command.requestID, phase: .unknown, error: .resultUnknown)
    }

    private func isCameraReplyReady(
        _ response: WatchExperimentResponse, for command: WatchExperimentCommand
    ) -> Bool {
        if response.phase == .failed { return true }
        if command.operation == .takePhoto, response.record?.phase == .capturing { return true }
        return response.phase == .completed
    }
}
