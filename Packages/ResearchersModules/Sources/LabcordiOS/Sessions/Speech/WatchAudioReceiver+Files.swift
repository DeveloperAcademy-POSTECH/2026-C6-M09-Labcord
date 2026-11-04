import Foundation
import LabcordShared

extension WatchAudioReceiver {
    nonisolated static var incomingRoot: URL {
        URL.applicationSupportDirectory.appending(path: "WatchAudioIncoming")
    }

    /// Call synchronously inside WCSession's didReceive-file callback, before returning.
    /// The system-owned incoming URL is temporary; this protected copy is never auto-deleted.
    nonisolated public static func retainIncomingFile(
        _ temporaryURL: URL, maximumBytes: Int = 256 * 1_024 * 1_024
    ) throws -> URL {
        let size = try temporaryURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard temporaryURL.isFileURL, size > 0, size <= 200_000 else {
            throw WatchAudioError.invalidAudio
        }
        let existing = (try? FileManager.default.contentsOfDirectory(
            at: incomingRoot, includingPropertiesForKeys: [.fileSizeKey]
        )) ?? []
        let used = existing.reduce(0) { total, url in
            total + ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        guard size <= maximumBytes, used <= maximumBytes - size else {
            throw WatchAudioError.storageFull
        }
        let destination = incomingRoot.appendingPathComponent("\(UUID().uuidString).chunk")
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        try FileManager.default.copyItem(at: temporaryURL, to: destination)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: destination.path
        )
        return destination
    }

    public func receiveRetainedFile(_ url: URL) async throws -> WatchAudioReceipt {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 200_000 else { throw WatchAudioError.invalidAudio }
        let data = try Data(contentsOf: url)
        guard data.count <= 200_000 else { throw WatchAudioError.invalidAudio }
        let chunk = try JSONDecoder().decode(WatchAudioChunk.self, from: data)
        return try await acceptRetainedChunk(chunk)
    }

}
