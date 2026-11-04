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
    enum RecordFilter: CaseIterable, Hashable {
        case all
        case photo
        case audio
        case video
        case timer
    }

    enum RecordSort: CaseIterable, Hashable {
        case oldest
        case newest
    }

    @ObservableState
    struct State: Equatable {
        let experimentID: UUID
        let isOpenedFromHome: Bool
        var recordTimeline: RecordTimelineFeature.State?
        var loadMessage: String?
        var selectedType: RecordFilter = .all
        var selectedSort: RecordSort = .oldest
        var titleEditOverlay: TitleEditOverlayFeature.State?

        init(experimentID: UUID, isOpenedFromHome: Bool = false) {
            self.experimentID = experimentID
            self.isOpenedFromHome = isOpenedFromHome
        }
    }

    enum Action: Equatable {
        case loadResultDetail
        case resultDetailLoaded(ExperimentResultDetail?)
        case resultDetailLoadFailed
        case recordFilterSelected(RecordFilter)
        case recordSortSelected(RecordSort)
        case recordTimeline(RecordTimelineFeature.Action)
        case editTapped
        case titleEditOverlay(TitleEditOverlayFeature.Action)
        case homeTapped
    }

    @Dependency(\.experimentClient) var experimentClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .loadResultDetail:
                state.recordTimeline = nil
                state.loadMessage = nil
                let experimentID = state.experimentID
                return .run { send in
                    async let minimumDisplay = Task.sleep(for: .seconds(1))
                    await Task.yield()
                    guard !Task.isCancelled else { return }

                    let detail: ExperimentResultDetail?
                    let loadFailed: Bool
                    do {
                        detail = try await experimentClient.loadResultDetail(experimentID)
                        loadFailed = false
                    } catch {
                        detail = nil
                        loadFailed = true
                    }

                    do {
                        try await minimumDisplay
                        try Task.checkCancellation()
                    } catch {
                        return
                    }

                    if loadFailed {
                        await send(.resultDetailLoadFailed)
                    } else {
                        await send(.resultDetailLoaded(detail))
                    }
                }

            case let .resultDetailLoaded(detail):
                state.recordTimeline = detail.map { RecordTimelineFeature.State(detail: $0) }
                state.loadMessage = detail == nil ? "실험을 찾을 수 없습니다." : nil
                return .none

            case .resultDetailLoadFailed:
                state.loadMessage = "실험을 불러오지 못했습니다."
                return .none

            case let .recordFilterSelected(filter):
                state.selectedType = filter
                return .none

            case let .recordSortSelected(sort):
                state.selectedSort = sort
                return .none

            case .editTapped:
                guard let title = state.recordTimeline?.detail.title else { return .none }
                state.titleEditOverlay = TitleEditOverlayFeature.State(
                    experimentID: state.experimentID,
                    originalTitle: title
                )
                return .none

            case let .titleEditOverlay(.delegate(.saved(detail))):
                guard detail.id == state.experimentID,
                      state.recordTimeline != nil else { return .none }
                state.titleEditOverlay = nil
                return .send(.recordTimeline(.detailUpdated(detail)))

            case .titleEditOverlay(.delegate(.dismiss)):
                state.titleEditOverlay = nil
                return .none

            case .titleEditOverlay:
                return .none

            case .recordTimeline:
                return .none

            case .homeTapped:
                return .none
            }
        }
        .ifLet(\.titleEditOverlay, action: \.titleEditOverlay) {
            TitleEditOverlayFeature()
        }
        .ifLet(\.recordTimeline, action: \.recordTimeline) {
            RecordTimelineFeature()
        }
    }
}
