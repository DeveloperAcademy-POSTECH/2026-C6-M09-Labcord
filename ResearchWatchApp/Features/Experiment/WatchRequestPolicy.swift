import LabcordShared

enum WatchRequestPolicy {
    static func canAbandon(_ operation: WatchExperimentCommand.Operation) -> Bool {
        isReadOnly(operation) || operation == .prepareStart
    }

    static func isReadOnly(_ operation: WatchExperimentCommand.Operation) -> Bool {
        operation == .list || operation == .snapshot
    }
}
