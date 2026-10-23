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

    init(connectivity: WatchConnectivitySession, requestKey: String) {
        self.connectivity = connectivity
        self.requestKey = requestKey
    }

    func request() {
        connectivity.activate()

        guard let session = connectivity.session else { return }

        if sendRequestIfReady(using: session) {
            cancel()
            return
        }

        guard activationObserverID == nil else { return }

        activationObserverID = connectivity.addStateObserver { [weak self] in
            guard let self,
                  self.activationObserverID != nil,
                  let session = self.connectivity.session,
                  self.sendRequestIfReady(using: session) else { return }

            self.cancel()
        }
    }

    func cancel() {
        guard let id = activationObserverID else { return }
        connectivity.removeStateObserver(id)
        activationObserverID = nil
    }

    private func sendRequestIfReady(using session: WCSession) -> Bool {
        guard session.activationState == .activated,
              session.isPaired,
              session.isWatchAppInstalled else { return false }

        session.transferUserInfo([requestKey: true])
        return true
    }
}
