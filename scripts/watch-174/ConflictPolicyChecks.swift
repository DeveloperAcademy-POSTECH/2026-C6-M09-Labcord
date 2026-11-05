import Foundation
import LabcordShared

@main
enum ConflictPolicyChecks {
    static func main() {
        let exclusive: [WatchExperimentCommand.Operation] = [
            .prepareStart, .start, .resume, .takePhoto, .startVideo, .stopVideo
        ]
        let targeted: [WatchExperimentCommand.Operation] = [
            .list, .snapshot, .requestStatus, .pause, .complete, .startTimer, .pauseTimer,
            .resumeTimer, .deleteTimer, .confirmRecord, .cancelRecord
        ]
        for operation in exclusive {
            precondition(WatchExperimentConflictPolicy.requiresExclusiveExperiment(operation),
                         "Exclusive operation must retain conflict protection: \(operation)")
        }
        for operation in targeted {
            precondition(!WatchExperimentConflictPolicy.requiresExclusiveExperiment(operation),
                         "Targeted operation is blocked by unrelated experiments: \(operation)")
        }
        let visibleSession: [WatchExperimentCommand.Operation] = exclusive + [.pause, .complete]
        let directTarget: [WatchExperimentCommand.Operation] = [
            .list, .snapshot, .requestStatus, .startTimer, .pauseTimer, .resumeTimer,
            .deleteTimer, .confirmRecord, .cancelRecord
        ]
        for operation in visibleSession {
            precondition(
                WatchExperimentConflictPolicy.requiresMatchingVisibleExperiment(operation),
                "Protect visible experiment: \(operation)"
            )
        }
        for operation in directTarget {
            precondition(
                !WatchExperimentConflictPolicy.requiresMatchingVisibleExperiment(operation),
                "Use target experiment ID: \(operation)"
            )
        }
        print("PASS: exclusive and targeted Watch operation conflict policy")
    }
}
