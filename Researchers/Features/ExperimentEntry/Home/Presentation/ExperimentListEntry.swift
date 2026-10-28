import LabcordiOS

extension ExperimentListEntry {
    var statusTitle: String {
        switch status {
        case .preparing: "준비"
        case .inProgress: "진행 중"
        case .paused: "일시 정지"
        case .completed: "종료"
        }
    }

}
