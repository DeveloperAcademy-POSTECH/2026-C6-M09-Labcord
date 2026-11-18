import Foundation
import LabcordShared

extension WatchExperimentClient {
    public func sendRecovering(
        _ command: WatchExperimentCommand,
        until isSatisfied: @Sendable (WatchExperimentResponse) -> Bool = { $0.phase == .completed }
    ) async throws -> WatchExperimentResponse {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(30))
        var next = command
        var mayHaveBeenDelivered = false

        while clock.now < deadline {
            try Task.checkCancellation()
            let response: WatchExperimentResponse
            do {
                response = try await send(next, before: deadline)
            } catch let error as WatchExperimentError {
                switch error {
                case .notReachable:
                    break
                case .deliveryTimeout, .resultUnknown:
                    mayHaveBeenDelivered = true
                    next = followUp(for: command)
                default:
                    throw error
                }
                try await clock.sleep(until: min(deadline, clock.now.advanced(by: .seconds(1))))
                continue
            }

            try Task.checkCancellation()
            mayHaveBeenDelivered = true
            if next.operation == .requestStatus, next.targetID == command.requestID,
               response.phase == .failed, response.queriedRequestID == nil {
                next = followUp(for: command)
                try await clock.sleep(until: min(deadline, clock.now.advanced(by: .seconds(1))))
                continue
            }
            if next.operation == .requestStatus,
               response.queriedRequestID != next.targetID,
               response.phase != .failed || response.queriedRequestID != nil {
                throw WatchExperimentError.invalidPayload
            }
            if response.phase == .failed {
                throw response.error ?? WatchExperimentError.resultUnknown
            }
            if response.phase != .unknown, isSatisfied(response) { return response }

            if response.phase == .unknown, next.operation == .requestStatus,
               next.targetID == command.requestID {
                next = command
            } else {
                next = followUp(for: command)
            }
            try await clock.sleep(until: min(deadline, clock.now.advanced(by: .milliseconds(200))))
        }
        try Task.checkCancellation()
        throw mayHaveBeenDelivered ? WatchExperimentError.resultUnknown : .notReachable
    }

    private func followUp(for command: WatchExperimentCommand) -> WatchExperimentCommand {
        switch command.operation {
        case .list, .screen, .snapshot, .requestStatus:
            return WatchExperimentCommand(
                operation: command.operation, experimentID: command.experimentID,
                targetID: command.targetID
            )
        default:
            return WatchExperimentCommand(
                operation: .requestStatus, experimentID: command.experimentID,
                targetID: command.requestID
            )
        }
    }

    private func send(
        _ command: WatchExperimentCommand, before deadline: ContinuousClock.Instant
    ) async throws -> WatchExperimentResponse {
        try await withThrowingTaskGroup(of: WatchExperimentResponse.self) { group in
            group.addTask { try await self.send(command) }
            group.addTask {
                try await ContinuousClock().sleep(until: deadline)
                throw WatchExperimentError.deliveryTimeout
            }
            defer { group.cancelAll() }
            guard let response = try await group.next() else { throw CancellationError() }
            return response
        }
    }
}
