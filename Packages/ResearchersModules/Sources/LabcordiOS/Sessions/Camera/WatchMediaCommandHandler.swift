import Foundation
import LabcordShared

public enum WatchMediaCommandHandler {
    public enum Input: Equatable, Sendable {
        case takePhoto(UUID)
        case startVideo(UUID)
        case stopVideo(UUID)
        case confirm(UUID)
        case cancel(UUID)
    }

    public static func input(
        for command: WatchExperimentCommand, activeExperimentID: UUID
    ) throws -> Input {
        guard command.experimentID == activeExperimentID else {
            throw WatchExperimentError.activeExperimentConflict
        }
        switch command.operation {
        case .takePhoto: return .takePhoto(command.targetID ?? command.requestID)
        case .startVideo: return .startVideo(command.targetID ?? command.requestID)
        case .stopVideo:
            guard let id = command.targetID else { throw WatchExperimentError.invalidPayload }
            return .stopVideo(id)
        case .confirmRecord:
            guard let id = command.targetID else { throw WatchExperimentError.invalidPayload }
            return .confirm(id)
        case .cancelRecord:
            guard let id = command.targetID else { throw WatchExperimentError.invalidPayload }
            return .cancel(id)
        default: throw WatchExperimentError.invalidPayload
        }
    }
}
