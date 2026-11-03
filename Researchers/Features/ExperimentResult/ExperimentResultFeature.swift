//
//  ExperimentResultFeature.swift
//  Researchers
//
//  Created by 정홍섭 on 10/29/26.
//

import ComposableArchitecture
import Foundation
import LabcordiOS
import LabcordShared

@Reducer
struct ExperimentResultFeature {
    enum RecordFilter: CaseIterable, Hashable {
        case all
        case photo
        case audio
        case video
        case timer

        func includes(_ type: RecordType) -> Bool {
            switch self {
            case .all: true
            case .photo: type == .photo
            case .audio: type == .audio
            case .video: type == .video
            case .timer: type == .timer
            }
        }
    }

    enum RecordSort: CaseIterable, Hashable {
        case oldest
        case newest
    }

    @ObservableState
    struct State: Equatable {
        let experimentID: UUID
        var detail: ExperimentResultDetail?
        var loadMessage: String?
        var selectedType: RecordFilter = .all
        var selectedSort: RecordSort = .oldest

        var displayedRecords: [ExperimentResultDetail.Record] {
            guard let detail else { return [] }

            let filteredRecords = detail.records.filter {
                selectedType.includes($0.type)
            }
            return filteredRecords.sorted { lhs, rhs in
                if lhs.recordedAt == rhs.recordedAt {
                    return selectedSort == .oldest
                        ? lhs.id.uuidString < rhs.id.uuidString
                        : lhs.id.uuidString > rhs.id.uuidString
                }
                return selectedSort == .oldest
                    ? lhs.recordedAt < rhs.recordedAt
                    : lhs.recordedAt > rhs.recordedAt
            }
        }
    }

    enum Action: Equatable {
        case loadResultDetail
        case resultDetailLoaded(ExperimentResultDetail?)
        case resultDetailLoadFailed
        case recordFilterSelected(RecordFilter)
        case recordSortSelected(RecordSort)
        case editTapped
        case homeTapped
        case resumeTapped
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

            case let .recordFilterSelected(filter):
                state.selectedType = filter
                return .none

            case let .recordSortSelected(sort):
                state.selectedSort = sort
                return .none

            case .editTapped, .homeTapped, .resumeTapped:
                return .none
            }
        }
    }
}
