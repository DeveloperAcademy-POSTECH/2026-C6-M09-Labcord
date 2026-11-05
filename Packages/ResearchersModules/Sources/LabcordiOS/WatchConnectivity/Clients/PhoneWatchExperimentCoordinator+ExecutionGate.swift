import Foundation
import LabcordShared

extension PhoneWatchExperimentCoordinator {
    func beginExecution(_ command: WatchExperimentCommand) throws {
        guard photoCancellationID == nil else { throw WatchExperimentError.phoneBusy }
        guard let activeID = executing else {
            executing = command.requestID
            return
        }
        guard let active = requests[activeID], active.response.phase == .processing,
              active.command.operation == .takePhoto, command.operation == .cancelRecord,
              let experimentID = command.experimentID,
              active.command.experimentID == experimentID,
              let targetID = command.targetID, active.command.targetID == targetID,
              command.requestID != activeID else {
            throw WatchExperimentError.phoneBusy
        }
        photoCancellationID = command.requestID
    }

    func finishExecution(_ requestID: UUID) {
        if executing == requestID { executing = nil }
        if photoCancellationID == requestID { photoCancellationID = nil }
    }
}
