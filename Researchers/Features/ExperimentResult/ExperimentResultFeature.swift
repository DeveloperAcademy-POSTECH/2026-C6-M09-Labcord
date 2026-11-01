//
//  ExperimentResultFeature.swift
//  Researchers
//
//  Created by 정홍섭 on 10/29/26.
//

import ComposableArchitecture
import Foundation
import LabcordiOS

@Reducer
struct ExperimentResultFeature {
    @ObservableState
    struct State: Equatable {
        let experimentID: UUID
        var detail: ExperimentResultDetail?
        var loadMessage: String?
    }

    enum Action: Equatable {
        case loadResultDetail
        case resultDetailLoaded(ExperimentResultDetail?)
        case resultDetailLoadFailed
        case homeTapped
    }

    @Dependency(\.experimentClient) var experimentClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .loadResultDetail:
                state.loadMessage = nil
                let experimentID = state.experimentID
                return .run { send in
                    do {
                        let detail = try await experimentClient.loadResultDetail(experimentID)
                        await send(.resultDetailLoaded(detail))
                    } catch {
                        await send(.resultDetailLoadFailed)
                    }
                }

            case let .resultDetailLoaded(detail):
                state.detail = detail
                state.loadMessage = detail == nil ? "실험을 찾을 수 없습니다." : nil
                return .none

            case .resultDetailLoadFailed:
                state.loadMessage = "실험을 불러오지 못했습니다."
                return .none

            case .homeTapped:
                return .none
            }
        }
    }
}
