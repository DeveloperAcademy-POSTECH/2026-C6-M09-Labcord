import Foundation
import LabcordShared

struct WatchExperimentRequestJournal {
    struct Entry: Codable {
        let command: WatchExperimentCommand
        var response: WatchExperimentResponse
    }

    private let url: URL
    private(set) var entries: [UUID: Entry]

    init(url: URL) throws {
        self.url = url
        if FileManager.default.fileExists(atPath: url.path) {
            entries = try JSONDecoder().decode([UUID: Entry].self, from: Data(contentsOf: url))
        } else {
            entries = [:]
        }
    }

    mutating func save(
        _ command: WatchExperimentCommand, response: WatchExperimentResponse
    ) throws {
        var updated = entries
        updated[command.requestID] = Entry(command: command, response: response)
        let data = try JSONEncoder().encode(updated)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        entries = updated
    }
}
