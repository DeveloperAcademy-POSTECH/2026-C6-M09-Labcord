import AVFAudio
import Foundation
import LabcordShared
import UIKit

extension PhoneWatchExperimentCoordinator {
    func validate(_ command: WatchExperimentCommand) throws -> WatchExperimentSnapshot {
        guard !isBusy else { throw WatchExperimentError.phoneBusy }
        guard UIApplication.shared.isProtectedDataAvailable else {
            throw WatchExperimentError.phoneUnlockRequired
        }
        guard let id = command.experimentID else { throw WatchExperimentError.invalidPayload }
        let current = try snapshot(id)
        guard command.expectedRevision == current.revision else {
            throw WatchExperimentError.staleRevision
        }
        if let visibleExperimentID, visibleExperimentID != id {
            throw WatchExperimentError.activeExperimentConflict
        }
        let active = try client.load().compactMap { try client.watchState($0.id) }
            .first { $0.experiment.status == .running && $0.experiment.id != id }
        guard active == nil else { throw WatchExperimentError.activeExperimentConflict }
        return current
    }

    func perform(
        _ command: WatchExperimentCommand, current: WatchExperimentSnapshot
    ) async throws -> UUID? {
        let id = current.experiment.id
        switch command.operation {
        case .prepareStart:
            guard current.experiment.status != .completed else {
                throw WatchExperimentError.invalidState
            }
            guard current.experiment.status == .running
                    || AVAudioApplication.shared.recordPermission == .granted else {
                throw WatchExperimentError.permissionDenied
            }
            tokens = tokens.filter { $0.value.expiresAt > .now }
            let issued = UUID()
            tokens[issued] = (id, .now.advanced(by: .seconds(3)))
            return issued
        case .start, .resume:
            try start(command, current: current)
        case .pause, .complete:
            try await close(command, current: current)
        default:
            guard let recordHandler else { throw WatchExperimentError.invalidState }
            let settlesRecord = [.confirmRecord, .cancelRecord].contains(command.operation)
            let closesTimer = command.operation == .deleteTimer
            guard [.running, .paused].contains(current.experiment.status)
                    || (current.experiment.status == .completed && (settlesRecord || closesTimer))
            else { throw WatchExperimentError.invalidState }
            if [.takePhoto, .startVideo].contains(command.operation) {
                guard current.experiment.status == .running else {
                    throw WatchExperimentError.invalidState
                }
                try consumeToken(command, experimentID: id)
            }
            try await recordHandler(command)
        }
        return nil
    }

    func start(_ command: WatchExperimentCommand, current: WatchExperimentSnapshot) throws {
        let id = current.experiment.id
        if current.experiment.status != .running {
            try consumeToken(command, experimentID: id)
            guard AVAudioApplication.shared.recordPermission == .granted else {
                throw WatchExperimentError.permissionDenied
            }
            guard [.ready, .paused].contains(current.experiment.status) else {
                throw WatchExperimentError.invalidState
            }
            guard try client.enterSessionAndLoadDetail(id) != nil else {
                throw WatchExperimentError.experimentNotFound
            }
        }
        pendingStartID = id
        commandSubscriber?.yield(.started(id))
    }

    func consumeToken(_ command: WatchExperimentCommand, experimentID: UUID) throws {
        guard let token = command.startToken,
              let prepared = tokens.removeValue(forKey: token),
              prepared.experimentID == experimentID, prepared.expiresAt > .now else {
            throw WatchExperimentError.requestExpired
        }
    }

    func close(
        _ command: WatchExperimentCommand, current: WatchExperimentSnapshot
    ) async throws {
        let id = current.experiment.id
        guard [.running, .paused].contains(current.experiment.status) else {
            throw WatchExperimentError.invalidState
        }
        if visibleExperimentID == id {
            try await prepareSessionClose?(command)
            guard let commandSubscriber else { throw WatchExperimentError.phoneBusy }
            try await withCheckedThrowingContinuation { continuation in
                completions[command.requestID] = continuation
                commandSubscriber.yield(.command(command))
            }
        } else if command.operation == .pause {
            try client.leaveSession(id, command.requestID, .now)
        } else {
            try client.complete(id, .now)
        }
        if pendingStartID == id { pendingStartID = nil }
    }
}
