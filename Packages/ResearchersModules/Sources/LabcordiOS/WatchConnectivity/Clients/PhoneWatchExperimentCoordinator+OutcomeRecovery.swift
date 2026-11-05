import Foundation
import LabcordShared

/// 외부 처리 이후 오류가 나 실행 여부를 판정할 수 없다.
struct WatchExecutionUncertain: Error {}

struct WatchDefinitiveRejection: Error {
    let error: WatchExperimentError
}

/// 이 프로세스에서 perform의 정상 반환이 확인된 요청만 복구한다.
struct WatchCompletedExecution {
    let experimentID: UUID
    let startToken: UUID?
    let record: WatchRecordSnapshot?
}

extension PhoneWatchExperimentCoordinator {
    func recoverCompletedExecution(_ entry: WatchExperimentRequestJournal.Entry) {
        let command = entry.command
        guard let completed = completedExecutions[command.requestID], journal != nil else {
            return
        }
        do {
            let response: WatchExperimentResponse
            if command.operation == .prepareStart, let token = completed.startToken,
               !validRecoveredToken(token, experimentID: completed.experimentID) {
                tokens.removeValue(forKey: token)
                response = failure(command, .requestExpired)
            } else {
                let updated = try snapshot(completed.experimentID)
                response = WatchExperimentResponse(
                    requestID: command.requestID, phase: .completed, snapshot: updated,
                    startToken: completed.startToken, record: completed.record
                )
            }
            let result = latestMediaResult(command, response: response)
            try journal?.save(command, response: result)
            requests[command.requestID]?.response = result
            if result.phase == .completed || result.phase == .failed {
                completedExecutions.removeValue(forKey: command.requestID)
                recordResults.removeValue(forKey: command.requestID)
            }
            if let snapshot = result.snapshot { publish(snapshot) }
        } catch {
            // 원래 요청은 재실행하지 않고 다음 조회에서 다시 확인한다.
        }
    }

    private func validRecoveredToken(_ token: UUID, experimentID: UUID) -> Bool {
        guard let stored = tokens[token] else { return false }
        return stored.0 == experimentID && stored.1 > .now
    }
}
