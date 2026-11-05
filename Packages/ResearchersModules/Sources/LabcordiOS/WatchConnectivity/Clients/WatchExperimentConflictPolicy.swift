import LabcordShared

enum WatchExperimentConflictPolicy {
    /// 시작·재개와 카메라 제어는 다른 실험을 방해하지 않도록 배타적으로 처리한다.
    static func requiresExclusiveExperiment(
        _ operation: WatchExperimentCommand.Operation
    ) -> Bool {
        switch operation {
        case .prepareStart, .start, .resume, .takePhoto, .startVideo, .stopVideo:
            true
        case .list, .snapshot, .requestStatus, .pause, .complete, .startTimer, .pauseTimer,
             .resumeTimer, .deleteTimer, .confirmRecord, .cancelRecord:
            false
        }
    }

    /// 중단·종료는 현재 iPhone 세션의 미디어 정리가 다른 실험에 적용되지 않도록 보호한다.
    static func requiresMatchingVisibleExperiment(
        _ operation: WatchExperimentCommand.Operation
    ) -> Bool {
        switch operation {
        case .prepareStart, .start, .resume, .pause, .complete, .takePhoto, .startVideo,
             .stopVideo:
            true
        case .list, .snapshot, .requestStatus, .startTimer, .pauseTimer, .resumeTimer,
             .deleteTimer, .confirmRecord, .cancelRecord:
            false
        }
    }
}
