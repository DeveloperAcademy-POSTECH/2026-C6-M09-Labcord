import Foundation

enum VoiceRecordingRecovery {

    static func installCopy(original: URL, destination: URL) throws {
        let files = FileManager.default
        if files.fileExists(atPath: destination.path) {
            guard files.contentsEqual(atPath: original.path, andPath: destination.path) else {
                throw CocoaError(.fileWriteFileExists)
            }
            return
        }
        let staged = destination.deletingLastPathComponent()
            .appending(path: ".voice-stage-\(UUID().uuidString).caf")
        defer { try? files.removeItem(at: staged) }
        try files.copyItem(at: original, to: staged)
        try files.moveItem(at: staged, to: destination)
    }

    static func recover(original: URL, saveAndVerify: (URL) throws -> Bool) -> Bool {
        guard FileManager.default.fileExists(atPath: original.path) else { return false }
        let copy = FileManager.default.temporaryDirectory
            .appending(path: "voice-recovery-\(UUID().uuidString).caf")
        do {
            try FileManager.default.copyItem(at: original, to: copy)
            defer { try? FileManager.default.removeItem(at: copy) }
            return try saveAndVerify(copy)
        } catch {
            return false
        }
    }
}
