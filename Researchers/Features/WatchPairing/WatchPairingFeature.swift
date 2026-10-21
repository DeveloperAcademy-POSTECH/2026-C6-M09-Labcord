//
//  WatchPairingFeature.swift
//  Researchers
//
//  Created by 정홍섭 on 10/21/26.
//

import Foundation
import ComposableArchitecture

@Reducer
struct WatchPairingFeature {
    @ObservableState
    struct State: Equatable {
        var isWatchReady: Bool? = nil
    }
    
    enum Action: Equatable {
        case onAppear
        case onDisappear
        case watchReadinessChanged(Bool?)
    }
    
    @Dependency(\.watchPairingClient) var watchPairingClient
    
    private nonisolated enum CancelID: Hashable, Sendable {
        case pairing
    }
    
    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                state.isWatchReady = nil
                
                return .run { send in
                    let stream = await watchPairingClient.statusStream()
                    
                    for await status in stream {
                        await send(.watchReadinessChanged(status))
                    }
                }
                .cancellable(id: CancelID.pairing, cancelInFlight: true)
                
            case let .watchReadinessChanged(status):
                state.isWatchReady = status
                return .none
                
            case .onDisappear:
                return .cancel(id: CancelID.pairing)
            }
        }
    }
}
