import Foundation

struct WatchTimerVisibilityStore {
    private struct Contents: Codable {
        var version = 1
        var dismissed: [String: Set<UUID>] = [:]
        var pending: [String: [String: Date]]?
        var pendingEndTimes: [String: [String: Date]]?
    }

    private let fileURL: URL

    init(fileURL: URL = URL.applicationSupportDirectory
        .appending(path: "WatchExperiment/dismissedTimers.json")) {
        self.fileURL = fileURL
    }

    func dismissedTimerIDs(experimentID: UUID) throws -> Set<UUID> {
        try load().dismissed[experimentID.uuidString] ?? []
    }

    struct PendingDeletion {
        let date: Date
        let effectiveEndTime: Date?
    }

    func pendingDeletions(experimentID: UUID) throws -> [UUID: PendingDeletion] {
        let contents = try load()
        let key = experimentID.uuidString
        let pending = contents.pending?[key] ?? [:]
        var result: [UUID: PendingDeletion] = [:]
        for (timerKey, date) in pending {
            guard let timerID = UUID(uuidString: timerKey), result[timerID] == nil else {
                throw CocoaError(.coderReadCorrupt)
            }
            result[timerID] = PendingDeletion(
                date: date, effectiveEndTime: contents.pendingEndTimes?[key]?[timerID.uuidString]
            )
        }
        return result
    }

    func beginDeletion(experimentID: UUID, timerID: UUID, endedAt: Date) throws {
        var contents = try load()
        let experimentKey = experimentID.uuidString
        guard contents.dismissed[experimentKey]?.contains(timerID) != true else { return }
        var pending = contents.pending ?? [:]
        if pending[experimentKey]?[timerID.uuidString] == nil {
            pending[experimentKey, default: [:]][timerID.uuidString] = endedAt
            contents.pending = pending
            var endTimes = contents.pendingEndTimes ?? [:]
            endTimes[experimentKey, default: [:]][timerID.uuidString] = endedAt
            contents.pendingEndTimes = endTimes
            try write(contents)
        }
    }

    func dismiss(experimentID: UUID, timerID: UUID) throws {
        var contents = try load()
        let key = experimentID.uuidString
        if contents.dismissed[key]?.contains(timerID) == true,
           contents.pending?[key]?[timerID.uuidString] == nil { return }
        contents.dismissed[key, default: []].insert(timerID)
        contents.pending?[key]?[timerID.uuidString] = nil
        contents.pendingEndTimes?[key]?[timerID.uuidString] = nil
        if contents.pendingEndTimes?[key]?.isEmpty == true { contents.pendingEndTimes?[key] = nil }
        if contents.pending?[key]?.isEmpty == true { contents.pending?[key] = nil }
        try write(contents)
    }

    private func write(_ contents: Contents) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        try JSONEncoder().encode(contents).write(
            to: fileURL, options: [.atomic, .completeFileProtection]
        )
    }

    private func load() throws -> Contents {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch CocoaError.fileReadNoSuchFile {
            return Contents()
        }
        let contents = try JSONDecoder().decode(Contents.self, from: data)
        guard contents.version == 1,
              contents.dismissed.keys.allSatisfy({ UUID(uuidString: $0) != nil }),
              (contents.pendingEndTimes ?? [:]).allSatisfy({ key, timers in
                  UUID(uuidString: key) != nil
                      && timers.keys.allSatisfy { UUID(uuidString: $0) != nil }
              }),
              (contents.pending ?? [:]).allSatisfy({ key, timers in
                  UUID(uuidString: key) != nil
                      && timers.keys.allSatisfy { UUID(uuidString: $0) != nil }
              }) else {
            throw CocoaError(.coderReadCorrupt)
        }
        return contents
    }
}
