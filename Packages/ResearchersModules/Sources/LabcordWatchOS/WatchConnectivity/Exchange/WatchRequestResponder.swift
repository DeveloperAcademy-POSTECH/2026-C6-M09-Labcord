//
//  WatchRequestResponder.swift
//  labcord-package-swift
//
//  Created by 정홍섭 on 10/21/26.
//

import Foundation
import LabcordShared

final class WatchRequestResponder {
    private let connectivity: WatchConnectivitySession
    private let requestKey: String
    private let response: () -> [String: Any]
    private var observerID: UUID?

    init(
        connectivity: WatchConnectivitySession,
        requestKey: String,
        response: @escaping () -> [String: Any]
    ) {
        self.connectivity = connectivity
        self.requestKey = requestKey
        self.response = response
    }

    func start() {
        guard observerID == nil else { return }

        observerID = connectivity.addUserInfoObserver { [self] userInfo in
            guard userInfo[requestKey] as? Bool == true else { return }

            var responseInfo = response()
            if let requestID = userInfo[WatchRequestMessage.requestIDKey] as? String {
                responseInfo[WatchRequestMessage.requestIDKey] = requestID
            }
            connectivity.transferUserInfo(responseInfo)
        }
    }
}
