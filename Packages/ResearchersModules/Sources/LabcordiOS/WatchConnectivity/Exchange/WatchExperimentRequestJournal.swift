import Foundation
import LabcordShared

/// 실행 전에 요청을 저장합니다. 재기동 시 처리 중이던 요청은 재실행하지 않습니다.
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
