//
//  WatchDeviceNameClient.swift
//  labcord-package-swift
//
//  Created by 정홍섭 on 10/21/26.
//

import ComposableArchitecture
import Foundation
import LabcordShared

public final class WatchDeviceNameClient {
    private let connectivity: WatchConnectivitySession
    private let requestSender: WatchRequestSender

    init(connectivity: WatchConnectivitySession) {
        self.connectivity = connectivity
        self.requestSender = WatchRequestSender(
            connectivity: connectivity,
            requestKey: WatchDeviceNameMessage.requestKey
        )
    }

    public func requestDeviceName() {
        requestSender.request()
    }

    public func cancelRequest() {
        requestSender.cancel()
    }

    public func deviceNameStream() -> AsyncStream<String> {
        WatchResponseStream.make(connectivity: connectivity) { [requestSender] userInfo in
            guard requestSender.matchesResponse(userInfo),
                  let name = userInfo[WatchDeviceNameMessage.nameKey] as? String,
                  !name.isEmpty else { return nil }
            return name
        }
    }
}

extension WatchDeviceNameClient: DependencyKey {
    public static var liveValue: WatchDeviceNameClient {
        @Dependency(\.watchConnectivitySession) var connectivity
        return WatchDeviceNameClient(connectivity: connectivity)
    }
}

extension DependencyValues {
    public var watchDeviceNameClient: WatchDeviceNameClient {
        get { self[WatchDeviceNameClient.self] }
        set { self[WatchDeviceNameClient.self] = newValue }
    }
}
