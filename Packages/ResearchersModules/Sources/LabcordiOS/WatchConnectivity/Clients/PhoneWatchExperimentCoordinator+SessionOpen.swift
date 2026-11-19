import Foundation
import LabcordShared
import UIKit
import UserNotifications

private struct StoredWatchSessionOpenRequest: Codable {
    let request: WatchSessionOpenRequest
    var handled: Bool
    var error: WatchExperimentError?
}

extension PhoneWatchExperimentCoordinator {
    private static var sessionOpenRequestKey: String { "watchSessionOpenRequest.v1" }

    public var hasPendingOpenSessionRequest: Bool {
        pendingOpenSession() != nil
    }

    public func receiveOpenSessionRequest(
        _ data: Data?, confirmed: Bool = false, replayOutcome: Bool = true
    ) {
        guard let data, data.count <= 4_096,
              let request = try? JSONDecoder().decode(WatchSessionOpenRequest.self, from: data)
        else { return }
        let action = request.action ?? .open
        if !confirmed, let watchOpenUnavailableBefore,
           request.requestedAt <= watchOpenUnavailableBefore { return }
        if confirmed && (action == .enteredExperiment || action == .leftExperiment) {
            receiveWatchPresence(request)
            return
        }
        guard canQueueOpenRequest(request, confirmed: confirmed, replayOutcome: replayOutcome)
        else { return }
        if action == .leftExperiment {
            storeOpenRequest(.init(request: request, handled: true))
            receiveWatchPresence(request)
            return
        }
        storeOpenRequest(.init(request: request, handled: action == .cancel))
        openSessionExpiryTask?.cancel()
        if action != .cancel { scheduleExpiry(request) }
        commandSubscriber?.yield(.openSessionRequested)
        if action == .enteredExperiment {
            commandSubscriber?.yield(.watchEnteredExperiment(request.experimentID))
        }
        if confirmed, action == .open, !UIApplication.shared.isProtectedDataAvailable {
            finishOpenSession(request.requestID, error: .phoneUnlockRequired)
        }
    }

    private func canQueueOpenRequest(
        _ request: WatchSessionOpenRequest, confirmed: Bool, replayOutcome: Bool
    ) -> Bool {
        let action = request.action ?? .open
        if let previous = storedOpenRequest() {
            if previous.request.requestID == request.requestID {
                if confirmed, request.epoch == stateEpoch, previous.handled, replayOutcome {
                    publishOpenOutcome(previous)
                }
                return false
            }
            guard request.supersedes(previous.request) else { return false }
            if action == .cancel, previous.handled,
               request.targetRequestID == previous.request.requestID { return false }
        }
        if let error = openRequestRejection(request, confirmed: confirmed) {
            if confirmed, action == .open, replayOutcome {
                publishOpenOutcome(request, error: error)
            }
            return false
        }
        return true
    }

    private func openRequestRejection(
        _ request: WatchSessionOpenRequest, confirmed: Bool
    ) -> WatchExperimentError? {
        if confirmed {
            guard request.epoch == stateEpoch else { return .staleRevision }
            guard request.expiresAt != nil,
                  request.action != .cancel || request.targetRequestID != nil else {
                return .invalidPayload
            }
        }
        return request.isLive(at: .now) ? nil : .requestExpired
    }

    public func pendingOpenSession() -> WatchSessionOpenRequest? {
        reconcileLatestSessionOpenRequest()
        guard let stored = storedOpenRequest(), !stored.handled else { return nil }
        let request = stored.request
        guard request.epoch == nil || request.epoch == stateEpoch else {
            finishOpenSession(request.requestID, error: .staleRevision)
            return nil
        }
        guard request.isLive(at: .now) else {
            finishOpenSession(request.requestID, error: .requestExpired)
            return nil
        }
        return request
    }

    public func canPrepareOpenSession(_ request: WatchSessionOpenRequest) -> Bool {
        do {
            try validateOpenSession(request)
            return true
        } catch {
            finishOpenSession(
                request.requestID, error: error as? WatchExperimentError ?? .storageFailed
            )
            return false
        }
    }

    public func commitOpenSession(
        _ requestID: UUID, experimentID: UUID
    ) throws -> ExperimentSessionDetail {
        guard let request = pendingOpenSession(), request.requestID == requestID,
              request.experimentID == experimentID else {
            throw WatchExperimentError.requestExpired
        }
        guard UIApplication.shared.applicationState == .active else {
            throw WatchExperimentError.phoneBusy
        }
        try validateOpenSession(request)
        guard let detail = try client.enterSessionAndLoadDetail(experimentID) else {
            throw WatchExperimentError.experimentNotFound
        }
        // iPhone의 MainActor에서 유효성 확인과 저장을 연달아 실행합니다.
        finishOpenSession(requestID)
        return detail
    }

    private func validateOpenSession(_ request: WatchSessionOpenRequest) throws {
        guard UIApplication.shared.isProtectedDataAvailable else {
            throw WatchExperimentError.phoneUnlockRequired
        }
        let summaries = try client.watchSummaries()
        guard summaries.contains(where: { $0.id == request.experimentID }) else {
            if try client.watchState(request.experimentID)?.experiment.status == .completed {
                throw WatchExperimentError.invalidState
            }
            throw WatchExperimentError.experimentNotFound
        }
        guard !summaries.contains(where: {
            $0.id != request.experimentID && $0.status == .running
        }) else { throw WatchExperimentError.activeExperimentConflict }
        guard request.isLive(at: .now) else { throw WatchExperimentError.requestExpired }
    }

    public func finishOpenSession(_ requestID: UUID, error: WatchExperimentError? = nil) {
        guard var stored = storedOpenRequest(), stored.request.requestID == requestID,
              !stored.handled else { return }
        stored.handled = true
        stored.error = error
        openSessionExpiryTask?.cancel()
        openSessionExpiryTask = nil
        storeOpenRequest(stored)
        if stored.request.expiresAt != nil { publishOpenOutcome(stored) }
    }

    private func scheduleExpiry(_ request: WatchSessionOpenRequest) {
        openSessionExpiryTask = Task { [weak self] in
            let delay = max(0, request.deadline.timeIntervalSinceNow)
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            finishOpenSession(request.requestID, error: .requestExpired)
            commandSubscriber?.yield(.openSessionRequested)
        }
    }

    func clearDebugOpenSessionRequest() {
        pendingWatchEntry = nil
        presentWatchExperimentID = nil
        reconcileLatestSessionOpenRequest()
        if let requestID = storedOpenRequest()?.request.requestID {
            finishOpenSession(requestID, error: .staleRevision)
        }
    }

    private func reconcileLatestSessionOpenRequest() {
        let context = connectivity.session?.receivedApplicationContext
        receiveOpenSessionRequest(context?[WatchSessionOpenRequest.messageKey] as? Data)
        receiveOpenSessionRequest(
            context?[WatchSessionOpenRequest.confirmedMessageKey] as? Data,
            confirmed: true, replayOutcome: false
        )
    }

    private func storedOpenRequest() -> StoredWatchSessionOpenRequest? {
        guard let data = UserDefaults.standard.data(forKey: Self.sessionOpenRequestKey) else {
            return nil
        }
        return try? JSONDecoder().decode(StoredWatchSessionOpenRequest.self, from: data)
    }

    private func storeOpenRequest(_ request: StoredWatchSessionOpenRequest) {
        guard let data = try? JSONEncoder().encode(request) else { return }
        UserDefaults.standard.set(data, forKey: Self.sessionOpenRequestKey)
    }

    private func publishOpenOutcome(_ stored: StoredWatchSessionOpenRequest) {
        publishOpenOutcome(stored.request, error: stored.error)
    }

    private func publishOpenOutcome(
        _ request: WatchSessionOpenRequest, error: WatchExperimentError?
    ) {
        let ack = WatchSessionOpenResponse(requestID: request.requestID, error: error)
        guard let session = connectivity.session, session.activationState == .activated,
              let data = try? JSONEncoder().encode(ack) else { return }
        let key = WatchSessionOpenResponse.messageKey
        var context = session.applicationContext
        context[key] = data
        try? session.updateApplicationContext(context)
        if session.isReachable {
            session.sendMessage([key: data], replyHandler: { _ in }, errorHandler: { _ in })
        }
    }

    public func pendingWatchEntryID() -> UUID? {
        guard let entry = pendingWatchEntry else { return nil }
        guard entry.isLive(at: .now), entry.epoch == nil || entry.epoch == stateEpoch else {
            pendingWatchEntry = nil
            return nil
        }
        return entry.experimentID
    }

    public func consumeWatchEntry(_ experimentID: UUID) {
        if pendingWatchEntry?.experimentID == experimentID { pendingWatchEntry = nil }
    }

    private func receiveWatchPresence(_ request: WatchSessionOpenRequest) {
        guard request.epoch == nil || request.epoch == stateEpoch,
              request.isLive(at: .now),
              latestWatchPresenceAt.map({ request.requestedAt > $0 }) ?? true else { return }
        latestWatchPresenceAt = request.requestedAt
        if request.action == .enteredExperiment {
            let isNewEntry = presentWatchExperimentID != request.experimentID
            presentWatchExperimentID = request.experimentID
            pendingWatchEntry = request
            if isNewEntry {
                commandSubscriber?.yield(.watchEnteredExperiment(request.experimentID))
            } else {
                commandSubscriber?.yield(.openSessionRequested)
            }
            return
        }
        if presentWatchExperimentID == request.experimentID { presentWatchExperimentID = nil }
        consumeWatchEntry(request.experimentID)
        guard currentScreen.destination == .experiment,
              currentScreen.experimentID == request.experimentID,
              (try? client.watchState(request.experimentID)?.experiment.status) == .running
        else { return }
        let content = UNMutableNotificationContent()
        content.title = "Apple Watch 연결이 끊어졌어요"
        content.body = "iPhone에서 기록해 주세요. Apple Watch를 사용하려면 다시 연결해 주세요."
        content.sound = .default
        let notification = UNNotificationRequest(
            identifier: "watch-left-\(request.experimentID.uuidString)", content: content,
            trigger: nil
        )
        Task { try? await UNUserNotificationCenter.current().add(notification) }
    }
}
