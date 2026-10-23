//
//  WatchRequestSender.swift
//  labcord-package-swift
//
//  Created by 정홍섭 on 10/23/26.
//

import Foundation
import LabcordShared
import WatchConnectivity

final class WatchRequestSender {
    private let connectivity: WatchConnectivitySession
    private let requestKey: String
    private var activationObserverID: UUID?
    private var currentRequestID: String?

    init(connectivity: WatchConnectivitySession, requestKey: String) {
        self.connectivity = connectivity
        self.requestKey = requestKey
    }

    func request() {
        currentRequestID = UUID().uuidString
        connectivity.activate()

        guard let session = connectivity.session else { return }

        if sendRequestIfReady(using: session) {
            stopObservingActivation()
            return
        }

        guard activationObserverID == nil else { return }

        activationObserverID = connectivity.addStateObserver { [weak self] in
            guard let self,
                  self.activationObserverID != nil,
                  let session = self.connectivity.session,
                  self.sendRequestIfReady(using: session) else { return }

            self.stopObservingActivation()
        }
    }

    func cancel() {
        currentRequestID = nil
        stopObservingActivation()
    }

    func matchesResponse(_ userInfo: [String: Any]) -> Bool {
        guard let currentRequestID else { return false }
        return userInfo[WatchRequestMessage.requestIDKey] as? String == currentRequestID
    }

    private func stopObservingActivation() {
        guard let id = activationObserverID else { return }
        connectivity.removeStateObserver(id)
        activationObserverID = nil
    }

    private func sendRequestIfReady(using session: WCSession) -> Bool {
        guard session.activationState == .activated,
              session.isPaired,
              session.isWatchAppInstalled else { return false }

        guard let currentRequestID else { return false }
        session.transferUserInfo([
            requestKey: true,
            WatchRequestMessage.requestIDKey: currentRequestID
        ])
        return true
    }
}
