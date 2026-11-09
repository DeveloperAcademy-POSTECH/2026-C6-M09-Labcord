import Foundation
import LabcordShared

enum WatchPendingDecisionKind: String, Codable, Sendable { case save, cancel }

private enum WatchPendingRequestKeys: String, CodingKey {
    case command, originalCapture, decisions
}

struct WatchPendingRequestJournal: Sendable {
    struct RecordDecision: Codable, Sendable {
        let experimentID: UUID
        let recordID: UUID
        let kind: WatchPendingDecisionKind
        var failed = false
    }

    private struct Entry: Codable {
        var command: WatchExperimentCommand?
        var originalCapture: WatchExperimentCommand?
        var decisions: [UUID: RecordDecision] = [:]

        init(command: WatchExperimentCommand? = nil) { self.command = command }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: WatchPendingRequestKeys.self)
            guard values.contains(.command) || values.contains(.decisions) else {
                throw WatchExperimentError.invalidPayload
            }
            command = try values.decodeIfPresent(WatchExperimentCommand.self, forKey: .command)
            originalCapture = try values.decodeIfPresent(
                WatchExperimentCommand.self, forKey: .originalCapture
            )
            decisions = try values.decodeIfPresent(
                [UUID: RecordDecision].self, forKey: .decisions
            ) ?? [:]
        }
    }

    let url: URL

    static let live = Self(url: URL.applicationSupportDirectory
        .appending(path: "WatchExperiment/pending-command.json"))

    func load() throws -> WatchExperimentCommand? { try read().command }

    func loadDecisions() throws -> [RecordDecision] { Array(try read().decisions.values) }

    func save(_ command: WatchExperimentCommand) throws {
        var entry = try read()
        if let previous = entry.command {
            guard previous == command else { throw WatchExperimentError.duplicateConflict }
            return
        }
        entry.command = command
        try recordDecision(command, in: &entry)
        try write(entry)
    }

    func supersedeCapture(with cancellation: WatchExperimentCommand) throws {
        var entry = try read()
        guard let original = entry.command, original.operation == .takePhoto,
              cancellation.operation == .cancelRecord,
              original.targetID != nil, original.targetID == cancellation.targetID,
              original.experimentID == cancellation.experimentID else {
            throw WatchExperimentError.duplicateConflict
        }
        entry.originalCapture = original
        entry.command = cancellation
        try recordDecision(cancellation, in: &entry)
        try write(entry)
    }

    func restoreCapture(after cancellationID: UUID) throws -> WatchExperimentCommand? {
        var entry = try read()
        guard let command = entry.command, command.requestID == cancellationID else {
            throw WatchExperimentError.duplicateConflict
        }
        guard let original = entry.originalCapture else { return nil }
        entry.command = original
        entry.originalCapture = nil
        if let id = command.targetID { entry.decisions[id]?.failed = true }
        try write(entry)
        return original
    }

    func markDecisionFailed(_ recordID: UUID) throws {
        var entry = try read()
        guard entry.decisions[recordID] != nil else { return }
        entry.decisions[recordID]?.failed = true
        try write(entry)
    }

    func clearDecision(experimentID: UUID, recordID: UUID) throws {
        var entry = try read()
        guard let decision = entry.decisions[recordID] else { return }
        guard decision.experimentID == experimentID else {
            throw WatchExperimentError.duplicateConflict
        }
        entry.decisions[recordID] = nil
        try write(entry)
    }

    func clear(_ requestID: UUID) throws {
        var entry = try read()
        guard let command = entry.command else { return }
        guard command.requestID == requestID else { throw WatchExperimentError.duplicateConflict }
        entry.command = nil
        entry.originalCapture = nil
        try write(entry)
    }

    private func recordDecision(_ command: WatchExperimentCommand, in entry: inout Entry) throws {
        guard command.operation == .confirmRecord || command.operation == .cancelRecord else {
            return
        }
        guard let experimentID = command.experimentID, let id = command.targetID else {
            throw WatchExperimentError.invalidPayload
        }
        if let previous = entry.decisions[id], previous.experimentID != experimentID {
            throw WatchExperimentError.duplicateConflict
        }
        entry.decisions[id] = RecordDecision(
            experimentID: experimentID, recordID: id,
            kind: command.operation == .cancelRecord ? .cancel : .save
        )
    }

    private func read() throws -> Entry {
        guard FileManager.default.fileExists(atPath: url.path) else { return Entry() }
        let data = try Data(contentsOf: url)
        let entry = try (try? JSONDecoder().decode(Entry.self, from: data))
            ?? Entry(command: JSONDecoder().decode(WatchExperimentCommand.self, from: data))
        if let command = entry.command {
            guard command.version == WatchExperimentCommand.schemaVersion,
                  command.experimentID != nil,
                  !WatchRequestPolicy.canAbandon(command.operation),
                  command.operation != .requestStatus else {
                throw WatchExperimentError.invalidPayload
            }
        }
        guard entry.decisions.allSatisfy({ $0.key == $0.value.recordID }) else {
            throw WatchExperimentError.invalidPayload
        }
        return entry
    }

    private func write(_ entry: Entry) throws {
        if entry.command == nil, entry.decisions.isEmpty {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            return
        }
        let data = try JSONEncoder().encode(entry)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(
            to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }
}
