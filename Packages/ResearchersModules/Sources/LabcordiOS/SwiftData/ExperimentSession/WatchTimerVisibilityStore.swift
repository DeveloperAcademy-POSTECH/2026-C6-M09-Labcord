import Foundation

struct WatchTimerVisibilityStore {
    private struct Contents: Codable {
        var version = 1
        var dismissed: [String: Set<UUID>] = [:]
    }

    private let fileURL: URL

    init(fileURL: URL = URL.applicationSupportDirectory
        .appending(path: "WatchExperiment/dismissedTimers.json")) {
        self.fileURL = fileURL
    }

    func dismissedTimerIDs(experimentID: UUID) throws -> Set<UUID> {
        try load().dismissed[experimentID.uuidString] ?? []
    }

    func dismiss(experimentID: UUID, timerID: UUID) throws {
        var contents = try load()
        let key = experimentID.uuidString
        guard contents.dismissed[key]?.contains(timerID) != true else { return }
        contents.dismissed[key, default: []].insert(timerID)
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
              contents.dismissed.keys.allSatisfy({ UUID(uuidString: $0) != nil }) else {
            throw CocoaError(.coderReadCorrupt)
        }
        return contents
    }
}
