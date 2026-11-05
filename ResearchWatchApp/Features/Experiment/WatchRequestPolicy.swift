import LabcordShared

/// 조회는 새 요청으로 복구할 수 있지만 변경 명령은 원래 요청 결과를 먼저 확인한다.
enum WatchRequestPolicy {
    static func canAbandon(_ operation: WatchExperimentCommand.Operation) -> Bool {
        isReadOnly(operation) || operation == .prepareStart
    }

    static func isReadOnly(_ operation: WatchExperimentCommand.Operation) -> Bool {
        operation == .list || operation == .snapshot
    }
}
