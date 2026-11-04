import ComposableArchitecture
import LabcordiOS

@Reducer
struct RecordTimelineFeature {
    @ObservableState
    struct State: Equatable {
        var detail: ExperimentResultDetail

        init(detail: ExperimentResultDetail) {
            self.detail = detail
        }

        var entries: [ExperimentResultDetail.TimelineEntry] {
            Array(detail.timeline.dropFirst())
        }
    }

    enum Action: Equatable {
        case detailUpdated(ExperimentResultDetail)
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .detailUpdated(detail):
                guard detail.id == state.detail.id else { return .none }
                state.detail = detail
                return .none
            }
        }
    }
}
