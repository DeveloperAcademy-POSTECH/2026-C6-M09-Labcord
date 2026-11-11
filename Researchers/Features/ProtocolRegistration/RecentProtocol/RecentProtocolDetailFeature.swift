import ComposableArchitecture
import LabcordiOS

@Reducer
struct RecentProtocolDetailFeature {
    struct TermGroup: Equatable {
        let title: String
        let terms: [String]
    }

    @ObservableState
    struct State: Equatable {
        let title: String
        let timerSeconds: [Int]
        let groups: [TermGroup]
        var expandedGroups: Set<String> = []

        init(entry: RecentProtocolEntry) {
            title = entry.title
            timerSeconds = entry.timerSeconds
            groups = [
                TermGroup(title: "시약·재료", terms: entry.materials),
                TermGroup(title: "샘플·분석 대상", terms: entry.samples),
                TermGroup(title: "실험 용어", terms: entry.glossaryTerms),
                TermGroup(title: "단위", terms: entry.units)
            ]
        }

        init(title: String, timerSeconds: [Int], groups: [TermGroup]) {
            self.title = title
            self.timerSeconds = timerSeconds
            self.groups = groups
        }
    }

    enum Action: Equatable {
        case expandedChanged(String, Bool)
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .expandedChanged(title, isExpanded):
                if isExpanded {
                    state.expandedGroups.insert(title)
                } else {
                    state.expandedGroups.remove(title)
                }
                return .none
            }
        }
    }
}
