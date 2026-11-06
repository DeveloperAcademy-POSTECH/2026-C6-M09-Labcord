import Foundation

enum VoiceRecordingJournal {
    struct Entry: Codable, Equatable, Sendable {
        var experimentID: UUID
        var recordingID: UUID
        var filePath: String
        var startedAt: Date
    }

    private static var directory: URL {
        URL.applicationSupportDirectory.appending(path: "VoiceRecordingJournals")
    }

    static func write(_ entry: Entry) {
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true
            )
            let url = directory.appending(path: "\(entry.recordingID.uuidString).json")
            try JSONEncoder().encode(entry).write(to: url, options: .atomic)
        } catch {
            return
        }
    }

    static func entries() -> [Entry] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return [] }
        return urls.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(Entry.self, from: data)
        }
    }

    static func remove(recordingID: UUID) {
        let url = directory.appending(path: "\(recordingID.uuidString).json")
        try? FileManager.default.removeItem(at: url)
    }

    static func remove(filePath: String) {
        for entry in entries() where entry.filePath == filePath {
            remove(recordingID: entry.recordingID)
        }
    }

    static func relocate(recordingID: UUID, to url: URL) {
        guard var entry = entries().first(where: { $0.recordingID == recordingID }) else { return }
        entry.filePath = url.path
        write(entry)
    }

    static func sweepUntrackedFiles() {
        let tracked = Set(entries().map(\.filePath))
        let incomplete = URL.applicationSupportDirectory
            .appending(path: "IncompleteVoiceRecordings")
        removeUntrackedCafFiles(at: incomplete, tracked: tracked, nested: true)
        removeUntrackedCafFiles(
            at: FileManager.default.temporaryDirectory, tracked: tracked, nested: false
        )
    }

    private static func removeUntrackedCafFiles(
        at root: URL, tracked: Set<String>, nested: Bool
    ) {
        let urls: [URL]
        if nested {
            guard let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: nil
            ) else { return }
            urls = enumerator.compactMap { $0 as? URL }
        } else {
            urls = (try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil
            )) ?? []
        }
        for url in urls where url.pathExtension == "caf" && !tracked.contains(url.path) {
            let name = url.lastPathComponent
            guard nested || name.hasPrefix("speech-") else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }
}
