import Foundation
import LabcordShared
import LabcordWatchOS

enum WatchCameraRequestEvent: Sendable {
    case prepared(WatchExperimentCommand)
    case rejected
    case received(WatchRecordSnapshot)
    case failed(WatchExperimentError)
}

enum WatchCameraCancellation: Equatable {
    case close, retake
}

struct WatchCameraRequests: Equatable {
    private var commands: [WatchExperimentCommand.Operation: WatchExperimentCommand] = [:]
    private var activeID: UUID?
    private var replaying = false
    private var operation: WatchExperimentCommand.Operation?
    private(set) var lastRecord: WatchRecordSnapshot?

    func isWaiting(for operation: WatchExperimentCommand.Operation) -> Bool {
        activeID != nil && self.operation == operation
    }

    var mayHaveCaptured: Bool {
        if let lastRecord {
            return lastRecord.phase != .failed || lastRecord.originalRetained != false
        }
        return commands[.takePhoto] != nil || commands[.startVideo] != nil
    }

    mutating func accept(_ record: WatchRecordSnapshot) -> Bool {
        if let previous = lastRecord {
            guard previous.phase != .saved, previous.phase != .cancelled,
                  record != previous else { return false }
            if let revision = previous.revision {
                guard let newer = record.revision, newer > revision else { return false }
            }
        }
        if record.phase == .failed, record.originalRetained == true {
            commands.removeValue(forKey: .confirmRecord)
        }
        lastRecord = record
        return true
    }

    mutating func begin(
        _ operation: WatchExperimentCommand.Operation, id: UUID, experimentID: UUID,
        recordID: UUID, kind: WatchRecordSnapshot.Kind
    ) -> WatchCameraRequest {
        activeID = id
        self.operation = operation
        return WatchCameraRequest(
            id: id, operation: operation, experimentID: experimentID,
            recordID: recordID, kind: kind, previous: commands[operation],
            captureRevision: (commands[.takePhoto] ?? commands[.startVideo])?.expectedRevision
        )
    }

    mutating func receive(
        _ event: WatchCameraRequestEvent, from id: UUID
    ) -> WatchExperimentCommand.Operation? {
        guard id == activeID, let operation else { return nil }
        switch event {
        case let .prepared(command):
            replaying = commands[operation] == command
            commands[operation] = command
        case .rejected:
            commands.removeValue(forKey: operation)
        case .received:
            activeID = nil
        case let .failed(error):
            activeID = nil
            switch error {
            case .notReachable, .phoneUnlockRequired:
                if !replaying { commands.removeValue(forKey: operation) }
            case .staleRevision, .requestExpired, .phoneBusy, .cameraUnavailable,
                 .permissionDenied, .invalidState, .experimentNotFound, .activeExperimentConflict:
                commands.removeValue(forKey: operation)
            default:
                break
            }
        }
        return operation
    }
}

struct WatchCameraRequest {
    let id: UUID
    let operation: WatchExperimentCommand.Operation
    let experimentID: UUID
    let recordID: UUID
    let kind: WatchRecordSnapshot.Kind
    let previous: WatchExperimentCommand?
    let captureRevision: UInt64?

    func run(
        using client: WatchExperimentClient,
        notify: (WatchCameraRequestEvent) async -> Void
    ) async {
        do {
            let command: WatchExperimentCommand
            if let previous {
                command = previous
            } else if operation == .cancelRecord {
                command = WatchExperimentCommand(
                    requestID: id, operation: operation, experimentID: experimentID,
                    expectedRevision: captureRevision, targetID: recordID
                )
            } else {
                command = try await prepare(using: client, requestID: id)
            }
            do {
                try await submit(command, using: client, notify: notify)
            } catch let error as WatchExperimentError
                where error == .requestExpired || error == .staleRevision {
                await notify(.rejected)
                try Task.checkCancellation()
                let refreshed = try await prepare(using: client, requestID: UUID())
                try await submit(refreshed, using: client, notify: notify)
            }
        } catch {
            guard !Task.isCancelled else { return }
            await notify(.failed((error as? WatchExperimentError) ?? .resultUnknown))
        }
    }

    private func submit(
        _ command: WatchExperimentCommand, using client: WatchExperimentClient,
        notify: (WatchCameraRequestEvent) async -> Void
    ) async throws {
        try Task.checkCancellation()
        await notify(.prepared(command))
        try Task.checkCancellation()
        let response = try await client.sendRecovering(command) { response in
            guard let record = response.record, record.kind == kind, record.id == command.targetID,
                  record.experimentID == command.experimentID else { return false }
            return Self.satisfied(command.operation, by: record.phase)
        }
        guard let record = response.record, record.kind == kind, record.id == recordID,
              record.experimentID == experimentID, Self.satisfied(operation, by: record.phase)
        else { throw WatchExperimentError.resultUnknown }
        await notify(.received(record))
    }

    private func prepare(
        using client: WatchExperimentClient, requestID: UUID
    ) async throws -> WatchExperimentCommand {
        let response = try await client.sendRecovering(WatchExperimentCommand(
            operation: .snapshot, experimentID: experimentID
        ))
        guard let snapshot = response.snapshot, snapshot.experiment.id == experimentID else {
            throw WatchExperimentError.resultUnknown
        }
        var revision = snapshot.revision
        var token: UUID?
        if operation == .takePhoto || operation == .startVideo {
            let preparation = try await client.sendRecovering(WatchExperimentCommand(
                operation: .prepareStart, experimentID: experimentID, expectedRevision: revision
            ))
            guard let issued = preparation.startToken else {
                throw WatchExperimentError.resultUnknown
            }
            revision = preparation.snapshot?.revision ?? revision
            token = issued
        }
        return WatchExperimentCommand(
            requestID: requestID, operation: operation, experimentID: experimentID,
            expectedRevision: revision, targetID: recordID, startToken: token
        )
    }

    nonisolated private static func satisfied(
        _ operation: WatchExperimentCommand.Operation, by phase: WatchRecordSnapshot.Phase
    ) -> Bool {
        switch phase {
        case .saved, .cancelled, .failed: true
        case .recording: operation == .startVideo
        case .previewing, .review: [.takePhoto, .startVideo, .stopVideo].contains(operation)
        default: false
        }
    }
}
