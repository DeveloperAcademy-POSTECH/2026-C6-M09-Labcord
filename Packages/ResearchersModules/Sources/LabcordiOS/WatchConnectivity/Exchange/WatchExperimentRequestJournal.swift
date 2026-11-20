import Foundation
import LabcordShared

struct WatchExperimentRequestJournal {
    struct Entry: Codable, Equatable {
        let command: WatchExperimentCommand
        var response: WatchExperimentResponse
    }

    static let entriesDirectoryName = "request-entries"
    private let entriesDirectory: URL
    private(set) var entries: [UUID: Entry]

    init(url: URL) throws {
        let files = FileManager.default
        entriesDirectory = url.deletingLastPathComponent()
            .appending(path: Self.entriesDirectoryName, directoryHint: .isDirectory)
        if files.fileExists(atPath: url.path) {
            entries = try JSONDecoder().decode([UUID: Entry].self, from: Data(contentsOf: url))
        } else {
            entries = [:]
        }
        try loadIndividualEntries()
    }

    private mutating func loadIndividualEntries() throws {
        let files = FileManager.default
        guard files.fileExists(atPath: entriesDirectory.path) else { return }
        let decoder = JSONDecoder()
        let urls = try files.contentsOfDirectory(
            at: entriesDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )
        for url in urls where url.pathExtension == "json" {
            let entry = try decoder.decode(Entry.self, from: Data(contentsOf: url))
            let id = entry.command.requestID
            guard UUID(uuidString: url.deletingPathExtension().lastPathComponent) == id else {
                throw WatchExperimentError.storageFailed
            }
            entries[id] = entry
        }
    }

    mutating func save(
        _ command: WatchExperimentCommand, response: WatchExperimentResponse
    ) throws {
        let id = command.requestID
        let entry = Entry(command: command, response: response)
        guard entries[id] != entry else { return }
        try FileManager.default.createDirectory(
            at: entriesDirectory, withIntermediateDirectories: true
        )
        let url = entriesDirectory.appending(path: "\(id.uuidString).json")
        try JSONEncoder().encode(entry).write(to: url, options: [.atomic, .completeFileProtection])
        entries[id] = entry
    }
}
