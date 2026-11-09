import Foundation

@MainActor
enum WatchAudioRetainedHandoff {
    static func deliver<Value>(
        url: URL, root: URL, archive: () async throws -> Value
    ) async throws -> Value {
        let receipt = try await archive()
        let parent = url.standardizedFileURL.deletingLastPathComponent()
        if parent == root.standardizedFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        return receipt
    }
}
