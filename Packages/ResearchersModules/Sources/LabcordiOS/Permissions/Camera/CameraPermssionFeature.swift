//
//  CameraPermssionFeature.swift
//  labcord-package-swift
//
//  Created by 정홍섭 on 10/26/26.
//

import ComposableArchitecture
import LabcordShared

@Reducer
public struct CameraPermssionFeature {
    @ObservableState
    public struct State: Equatable {
        public var status: PermissionStatus?

        public init() {}
    }

    public enum Action: Equatable {
        case check
        case statusUpdated(PermissionStatus)
        case request
    }

    @Dependency(\.cameraPermissionClient) var cameraPermissionClient

    public init() {}

    public var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .check:
                return .run { send in
                    let status = await cameraPermissionClient.currentStatus()
                    await send(.statusUpdated(status))
                }

            case let .statusUpdated(status):
                state.status = status
                return .none

            case .request:
                return .run { send in
                    let status = await cameraPermissionClient.requestAccess()
                    await send(.statusUpdated(status))
                }
            }
        }
    }
}
