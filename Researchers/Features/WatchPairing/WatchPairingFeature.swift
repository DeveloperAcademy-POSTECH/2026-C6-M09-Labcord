//
//  WatchPairingFeature.swift
//  Researchers
//
//  Created by 정홍섭 on 10/21/26.
//

import ComposableArchitecture
import Foundation

@Reducer
struct WatchPairingFeature {
    @ObservableState
    struct State: Equatable {
        var isWatchReady: Bool?
        var watchDeviceName: String?
        var batteryLevel: Float?
        var didReciveBatteryResponse = false
    }

    enum Action: Equatable {
        case onAppear
        case onDisappear
        case watchReadinessChanged(Bool?)
        case deviceNameChanged(String)
        case batteryLevelChanged(Float?)
    }

    @Dependency(\.watchPairingClient) var watchPairingClient
    @Dependency(\.watchBatteryClient) var watchBatteryClient
    @Dependency(\.watchDeviceNameClient) var watchDeviceNameClient

    private nonisolated enum CancelID: Hashable, Sendable {
        case pairing
        case battery
        case deviceName
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                state.isWatchReady = nil
                state.watchDeviceName = nil
                state.batteryLevel = nil
                state.didReciveBatteryResponse = false

                return .merge(
                    .run { send in
                        let stream = await watchPairingClient.statusStream()

                        for await status in stream {
                            await send(.watchReadinessChanged(status))
                        }
                    }
                    .cancellable(id: CancelID.pairing, cancelInFlight: true),

                    .run { send in
                        let stream = await watchBatteryClient.batteryStream()
                        await watchBatteryClient.requestBatteryLevel()

                        for await level in stream {
                            await send(.batteryLevelChanged(level))
                        }
                    }
                    .cancellable(id: CancelID.battery, cancelInFlight: true),

                    .run { send in
                        let stream = await watchDeviceNameClient.deviceNameStream()
                        await watchDeviceNameClient.requestDeviceName()

                        for await name in stream {
                            await send(.deviceNameChanged(name))
                        }
                    }
                    .cancellable(id: CancelID.deviceName, cancelInFlight: true)
                )

            case let .watchReadinessChanged(status):
                state.isWatchReady = status
                if status == false {
                    state.watchDeviceName = nil
                }
                return .none

            case let .deviceNameChanged(name):
                state.watchDeviceName = name
                return .none

            case let .batteryLevelChanged(level):
                state.batteryLevel = level
                state.didReciveBatteryResponse = true
                return .none

            case .onDisappear:
                return .merge(
                    .cancel(id: CancelID.pairing),
                    .cancel(id: CancelID.battery),
                    .cancel(id: CancelID.deviceName)
                )
            }
        }
    }
}
