import Foundation
import LabcordShared
import UIKit

private struct StoredWatchSessionOpenRequest: Codable {
    let request: WatchSessionOpenRequest
    var handled: Bool
}

extension PhoneWatchExperimentCoordinator {
    private static var sessionOpenRequestKey: String { "watchSessionOpenRequest.v1" }

    public var hasPendingOpenSessionRequest: Bool {
        storedOpenRequest()?.handled == false
    }

    public func receiveOpenSessionRequest(_ data: Data?) {
        guard let data, data.count <= 4_096,
              let request = try? JSONDecoder().decode(
                WatchSessionOpenRequest.self, from: data
              ) else { return }
        if let previous = storedOpenRequest(),
           previous.request.requestID == request.requestID
            || previous.request.requestedAt > request.requestedAt { return }
        storeOpenRequest(.init(request: request, handled: false))
        commandSubscriber?.yield(.openSessionRequested)
    }

    public func pendingOpenSessionID() -> UUID? {
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
