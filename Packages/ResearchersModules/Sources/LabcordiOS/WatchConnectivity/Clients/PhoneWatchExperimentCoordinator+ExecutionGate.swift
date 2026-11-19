import Foundation
import LabcordShared

extension PhoneWatchExperimentCoordinator {
    func beginExecution(_ command: WatchExperimentCommand) throws {
        guard interruptingMediaRequestID == nil else { throw WatchExperimentError.phoneBusy }
        guard let activeID = executing else {
            executing = command.requestID
            return
        }
        guard let active = requests[activeID], active.response.phase == .processing,
              command.canInterruptCameraCommand(active.command) else {
            throw WatchExperimentError.phoneBusy
        }
        interruptingMediaRequestID = command.requestID
    }

    func finishExecution(_ requestID: UUID) {
        if executing == requestID { executing = nil }
        if interruptingMediaRequestID == requestID { interruptingMediaRequestID = nil }
    }
}
