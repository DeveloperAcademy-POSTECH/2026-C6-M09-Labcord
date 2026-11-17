import Foundation
import LabcordShared
import UIKit
import UserNotifications

private struct StoredWatchSessionOpenRequest: Codable {
    let request: WatchSessionOpenRequest
    var handled: Bool
}

extension PhoneWatchExperimentCoordinator {
    private static var sessionOpenRequestKey: String { "watchSessionOpenRequest.v1" }

    public var hasPendingOpenSessionRequest: Bool {
        reconcileLatestSessionOpenRequest()
        return storedOpenRequest()?.handled == false
    }

    public func receiveOpenSessionRequest(_ data: Data?) {
        guard let data, data.count <= 4_096,
              let request = try? JSONDecoder().decode(
                WatchSessionOpenRequest.self, from: data
              ) else { return }
        if let previous = storedOpenRequest() {
            guard previous.request.requestedAt < request.requestedAt else { return }
            if request.action == .cancel,
               previous.request.experimentID != request.experimentID { return }
        }
        let action = request.action ?? .open
        storeOpenRequest(.init(request: request, handled: action != .open))
        switch action {
        case .open:
            commandSubscriber?.yield(.openSessionRequested)
        case .leftExperiment:
            guard currentScreen.destination == .experiment,
                  currentScreen.experimentID == request.experimentID,
                  (try? client.watchState(request.experimentID)?.experiment.status) == .running
            else { return }
            let content = UNMutableNotificationContent()
            content.title = "Apple Watch 연결이 끊어졌어요"
            content.body = "iPhone에서 기록해 주세요. "
                + "Apple Watch를 사용하려면 다시 연결해 주세요."
            content.sound = .default
            let notification = UNNotificationRequest(
                identifier: "watch-left-\(request.experimentID.uuidString)",
                content: content, trigger: nil
            )
            Task { try? await UNUserNotificationCenter.current().add(notification) }
        case .cancel:
            break
        }
    }

    public func pendingOpenSessionID() -> UUID? {
        reconcileLatestSessionOpenRequest()
        guard UIApplication.shared.isProtectedDataAvailable,
              let stored = storedOpenRequest(), !stored.handled else { return nil }
        let id = stored.request.experimentID
        do {
            guard let experiment = try client.watchState(id)?.experiment,
                  experiment.status != .completed else {
                didHandleOpenSession(id)
                return nil
            }
            return id
        } catch { return nil }
    }

    public func didHandleOpenSession(_ id: UUID) {
        guard var stored = storedOpenRequest(), stored.request.experimentID == id,
              !stored.handled else { return }
        stored.handled = true
        storeOpenRequest(stored)
    }

    private func reconcileLatestSessionOpenRequest() {
        receiveOpenSessionRequest(
            connectivity.session?.receivedApplicationContext[
                WatchSessionOpenRequest.messageKey
            ] as? Data
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
}
