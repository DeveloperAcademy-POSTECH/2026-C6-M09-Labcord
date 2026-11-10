import Foundation
import LabcordShared

public extension ExperimentResultDetail {
    var timerIdentityOrderByRecordID: [UUID: Int] {
        let timerRecords = records.filter { $0.type == .timer }.sorted {
            if $0.recordedAt != $1.recordedAt { return $0.recordedAt < $1.recordedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        return Dictionary(uniqueKeysWithValues: timerRecords.enumerated().map { index, record in
            (record.id, index)
        })
    }
}
