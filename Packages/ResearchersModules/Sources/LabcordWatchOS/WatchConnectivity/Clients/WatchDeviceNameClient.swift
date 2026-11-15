//
//  WatchDeviceNameClient.swift
//  labcord-package-swift
//
//  Created by 정홍섭 on 10/21/26.
//

import ComposableArchitecture
import LabcordShared
import WatchKit

public final class WatchDeviceNameClient {
    private let responder: WatchRequestResponder

    init(connectivity: WatchConnectivitySession) {
        self.responder = WatchRequestResponder(
            connectivity: connectivity,
            requestKey: WatchDeviceNameMessage.requestKey
        ) {
            return [WatchDeviceNameMessage.nameKey: WKInterfaceDevice.current().model]
        }
    }

    public func start() {
        responder.start()
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
