import Foundation
import LabcordShared
import WatchConnectivity

extension WatchConnectivitySession {
    public func requestPhoneSession(_ request: WatchSessionOpenRequest) async throws {
        try Task.checkCancellation()
        try await waitForActivation()
        guard request.isLive(at: .now) else { throw WatchExperimentError.requestExpired }
        guard request.epoch == experiments.remoteEpoch else {
            throw WatchExperimentError.staleRevision
        }
        guard registerOpenTransmission(request) else { throw WatchExperimentError.requestExpired }
        let id = request.requestID
        let (stream, continuation) = AsyncStream<WatchSessionOpenResponse>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        openAcks[id] = continuation
        let deadline = Task {
            try? await Task.sleep(for: .seconds(max(0, request.deadline.timeIntervalSinceNow)))
            if !Task.isCancelled { continuation.finish() }
        }
        defer {
            deadline.cancel()
            openAcks.removeValue(forKey: id)
            continuation.finish()
        }
        sendSessionOpenRequest(request, saveInContext: true)
        for await response in stream {
            try Task.checkCancellation()
            guard request.isLive(at: .now) else { throw WatchExperimentError.deliveryTimeout }
            guard request.epoch == experiments.remoteEpoch else {
                throw WatchExperimentError.staleRevision
            }
            if let error = response.error { throw error }
            return
        }
        try Task.checkCancellation()
        throw WatchExperimentError.deliveryTimeout
    }

    public func cancelPhoneSession(_ request: WatchSessionOpenRequest) async {
        openAcks[request.requestID]?.finish()
        guard request.isLive(at: .now) else { return }
        let cancellation = request.cancellation()
        guard registerOpenTransmission(cancellation) else { return }
        try? await waitForActivation()
        guard lastOpenTransmission?.requestID == cancellation.requestID else { return }
        sendSessionOpenRequest(cancellation, saveInContext: true)
    }

    private func registerOpenTransmission(_ request: WatchSessionOpenRequest) -> Bool {
        guard lastOpenTransmission.map({ request.supersedes($0) }) ?? true else { return false }
        lastOpenTransmission = request
        return true
    }

    public func enterPhoneSession(_ experimentID: UUID) {
        sendPresence(experimentID, action: .enteredExperiment)
    }

    public func leavePhoneSession(_ experimentID: UUID) {
        sendPresence(experimentID, action: .leftExperiment)
    }

    private func sendPresence(_ experimentID: UUID, action: WatchSessionOpenRequest.Action) {
        sendSessionOpenRequest(
            WatchSessionOpenRequest(
                experimentID: experimentID, action: action, epoch: experiments.remoteEpoch
            ),
            saveInContext: false
        )
    }

    func resendPendingSessionOpenRequest() {
        guard let request = lastOpenTransmission,
              request.epoch == experiments.remoteEpoch,
              request.action == .cancel || openAcks[request.requestID] != nil
        else { return }
        sendSessionOpenRequest(request, saveInContext: true)
    }

    private func sendSessionOpenRequest(_ request: WatchSessionOpenRequest, saveInContext: Bool) {
        guard let session, WatchConnectivityState(session).canTransfer,
              request.isLive(at: .now),
              let data = try? JSONEncoder().encode(request) else { return }
        let key = WatchSessionOpenRequest.confirmedMessageKey
        let id = request.requestID.uuidString
        if saveInContext {
            _ = try? WatchConnectivityDiagnostics.updateContext(session, key: key, data: data)
        }
        if session.isReachable {
            WatchConnectivityDiagnostics.event("open.sent", id: id, bytes: data.count)
            session.sendMessage([key: data], replyHandler: { _ in
                WatchConnectivityDiagnostics.event("open.reply", id: id)
            }, errorHandler: { error in
                WatchConnectivityDiagnostics.failure("open.failed", id: id, error: error)
            })
        }
        transferUserInfo([key: data])
    }

    func receiveOpenAck(_ data: Data) {
        guard data.count <= 4_096,
              let ack = try? JSONDecoder().decode(WatchSessionOpenResponse.self, from: data)
        else { return }
        openAcks[ack.requestID]?.yield(ack)
    }
}
