import Foundation

@MainActor
enum VoiceRecordingJournal {
    private static var ownedRecordingIDs: Set<UUID> = []

    struct Entry: Codable, Equatable, Sendable {
        var experimentID: UUID
        var recordingID: UUID
        var filePath: String
        var startedAt: Date
    }

    private static var directory: URL {
        URL.applicationSupportDirectory.appending(path: "VoiceRecordingJournals")
    }

    static func beginOwnedRecording(_ entry: Entry) throws {
        ownedRecordingIDs.insert(entry.recordingID)
        do {
            try write(entry)
        } catch {
            ownedRecordingIDs.remove(entry.recordingID)
            throw error
        }
    }

    static func recoverableEntries(in entries: [Entry]) -> [Entry] {
        entries.filter { !ownedRecordingIDs.contains($0.recordingID) }
    }

    private static func write(_ entry: Entry) throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        let url = directory.appending(path: "\(entry.recordingID.uuidString).json")
        try JSONEncoder().encode(entry).write(to: url, options: .atomic)
    }

    struct Scan {
        var entries: [Entry]
        var unreadableCount: Int
        var directoryUnavailable: Bool
    }

    static func scan() -> Scan {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return Scan(entries: [], unreadableCount: 0, directoryUnavailable: false)
        }
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else {
            return Scan(entries: [], unreadableCount: 0, directoryUnavailable: true)
        }
        var entries: [Entry] = []
        var unreadableCount = 0
        for url in urls {
            guard let data = try? Data(contentsOf: url),
                  let entry = try? JSONDecoder().decode(Entry.self, from: data) else {
                unreadableCount += 1
                continue
            }
            entries.append(entry)
        }
        return Scan(
            entries: entries, unreadableCount: unreadableCount, directoryUnavailable: false
        )
    }

    static func remove(recordingID: UUID) {
        let url = directory.appending(path: "\(recordingID.uuidString).json")
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            ownedRecordingIDs.remove(recordingID)
        } catch {
            SpeechDebugLog.write("voice journal cleanup failed")
        }
    }

    static func remove(filePath: String) {
        for entry in scan().entries where entry.filePath == filePath {
            remove(recordingID: entry.recordingID)
        }
    }

    static func relocate(recordingID: UUID, to url: URL) throws {
        guard var entry = scan().entries.first(where: { $0.recordingID == recordingID }) else {
            return
        }
        entry.filePath = url.path
        try write(entry)
    }

}
