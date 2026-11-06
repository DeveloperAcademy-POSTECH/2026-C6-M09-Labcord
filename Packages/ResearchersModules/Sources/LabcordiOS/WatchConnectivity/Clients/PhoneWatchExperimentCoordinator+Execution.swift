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
        if WatchExperimentConflictPolicy.requiresMatchingVisibleExperiment(command.operation),
           let visibleExperimentID, visibleExperimentID != id {
            throw WatchExperimentError.activeExperimentConflict
        }
        if WatchExperimentConflictPolicy.requiresExclusiveExperiment(command.operation) {
            let active = try client.loadForWatch().compactMap { try client.watchState($0.id) }
                .first { $0.experiment.status == .running && $0.experiment.id != id }
            guard active == nil else { throw WatchExperimentError.activeExperimentConflict }
        }
        return current
    }

    func perform(
        _ command: WatchExperimentCommand, current: WatchExperimentSnapshot
    ) async throws -> UUID? {
        let id = current.experiment.id
        switch command.operation {
        case .prepareStart:
            guard current.experiment.status == .running
                    || AVAudioApplication.shared.recordPermission == .granted else {
                throw WatchExperimentError.permissionDenied
            }
            tokens = tokens.filter { $0.value.1 > .now }
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
            try await executeRecordHandler(recordHandler, command: command)
        }
        return nil
    }

    private func executeRecordHandler(
        _ handler: (WatchExperimentCommand) async throws -> Void,
        command: WatchExperimentCommand
    ) async throws {
        do {
            try await handler(command)
        } catch let rejection as WatchDefinitiveRejection {
            throw rejection.error
        } catch {
            // handler가 저장·기기 명령을 시작한 뒤 실패했을 수 있다.
            throw WatchExecutionUncertain()
        }
    }

    func start(_ command: WatchExperimentCommand, current: WatchExperimentSnapshot) throws {
        let id = current.experiment.id
        if current.experiment.status != .running {
            try consumeToken(command, experimentID: id)
            guard AVAudioApplication.shared.recordPermission == .granted else {
                throw WatchExperimentError.permissionDenied
            }
            let canResumeCompleted = command.operation == .resume
                && current.experiment.status == .completed
            guard canResumeCompleted || [.ready, .paused].contains(current.experiment.status)
            else {
                throw WatchExperimentError.invalidState
            }
            if current.experiment.status == .completed {
                do { try client.resumeCompleted(id, .now) } catch {
                    throw WatchExecutionUncertain()
                }
            } else {
                do { try client.enterSession(id, .now) } catch {
                    throw WatchExecutionUncertain()
                }
            }
        }
        pendingStartID = id
        commandSubscriber?.yield(.started(id))
    }

    func consumeToken(_ command: WatchExperimentCommand, experimentID: UUID) throws {
        guard let token = command.startToken,
              let prepared = tokens.removeValue(forKey: token),
              prepared.0 == experimentID, prepared.1 > .now else {
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
            guard let commandSubscriber else { throw WatchExperimentError.phoneBusy }
            let prepare = prepareSessionClose
            do {
                try await prepare?(command)
                try await withCheckedThrowingContinuation { continuation in
                    completions[command.requestID] = continuation
                    commandSubscriber.yield(.command(command))
                }
            } catch let rejection as WatchDefinitiveRejection {
                guard prepare == nil else { throw WatchExecutionUncertain() }
                throw rejection.error
            } catch {
                throw WatchExecutionUncertain()
            }
        } else {
            do {
                if command.operation == .pause {
                    try client.leaveSession(id, command.requestID, .now)
                } else {
                    try client.complete(id, .now)
                }
            } catch {
                throw WatchExecutionUncertain()
            }
        }
        if pendingStartID == id { pendingStartID = nil }
    }
}
