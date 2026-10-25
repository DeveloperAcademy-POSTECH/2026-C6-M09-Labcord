//
//  CameraPermssionFeature.swift
//  labcord-package-swift
//
//  Created by 정홍섭 on 10/26/26.
//

import ComposableArchitecture
import Foundation

@Reducer
public struct CameraPermssionFeature {
    @ObservableState
    public struct State: Equatable {
        public var status: CameraPermissionStatus?
        
        public init() {}
    }
    
    public enum Action: Equatable {
        case check
        case statusUpdated(CameraPermissionStatus)
        case request
        case openSettingsTapped
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
                
            case .openSettingsTapped:
                guard state.status == .denied else {
                    return .none
                }
                
                return .run { _ in
                    _ = await cameraPermissionClient.openSettings()
                }
            }
        }
    }
}
