import Foundation
import LabcordShared

struct WatchExperimentQueryCache {
    private let limit: Int
    private var entries: [UUID: WatchExperimentRequestJournal.Entry] = [:]
    private var order: [UUID] = []

    init(limit: Int = 128) {
        precondition(limit > 0)
        self.limit = limit
    }

    func response(for command: WatchExperimentCommand) -> WatchExperimentResponse? {
        guard let entry = entries[command.requestID] else { return nil }
        guard entry.command == command else {
            return WatchExperimentResponse(
                requestID: command.requestID, phase: .failed, error: .duplicateConflict
            )
        }
        return entry.response
    }

    func response(for requestID: UUID) -> WatchExperimentResponse? {
        entries[requestID]?.response
    }

    mutating func store(_ command: WatchExperimentCommand, response: WatchExperimentResponse) {
        guard entries[command.requestID] == nil else { return }
        if order.count == limit { entries.removeValue(forKey: order.removeFirst()) }
        order.append(command.requestID)
        entries[command.requestID] = .init(command: command, response: response)
    }
}
