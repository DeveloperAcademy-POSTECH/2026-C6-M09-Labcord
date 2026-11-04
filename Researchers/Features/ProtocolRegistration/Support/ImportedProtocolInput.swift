import CoreTransferable
import Foundation
import UniformTypeIdentifiers

nonisolated struct ImportedProtocolInput: Identifiable, Equatable, Sendable, Transferable {
    private static let parserSafetyMaximumInputBytes = 100 * 1024 * 1024
    private static let minimumFreeBytes: Int64 = 100 * 1024 * 1024
    let id: UUID
    let url: URL
    let name: String
    private let ownership: ImportedInputOwnership
    private let isRecovered: Bool

    private init(id: UUID, url: URL, name: String, removeOnRelease: Bool = true) {
        self.id = id
        self.url = url
        self.name = name
        self.ownership = ImportedInputOwnership(url: url, removeOnRelease: removeOnRelease)
        self.isRecovered = !removeOnRelease
    }

    static func recovered(id: UUID, url: URL, name: String) -> Self {
        Self(id: id, url: url, name: name, removeOnRelease: false)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.url == rhs.url && lhs.name == rhs.name
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            try copyOwned(received.file, useSecurityScope: false)
        }
    }

    static func copyFile(_ source: URL) async throws -> Self {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try copyOwned(source, useSecurityScope: true))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func preservedCopy() async throws -> Self {
        guard isRecovered else { return self }
        let result: Self = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try Self.copyOwned(
                        self.url, useSecurityScope: false, inputID: self.id, inputName: self.name
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        try Task.checkCancellation()
        return result
    }

    private static func copyOwned(
        _ source: URL, useSecurityScope: Bool, inputID: UUID? = nil, inputName: String? = nil
    ) throws -> Self {
        let id = inputID ?? UUID()
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent("labcord-protocol-\(UUID().uuidString)")
            .appendingPathExtension(source.pathExtension)
        let scoped = useSecurityScope && source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        do {
            if useSecurityScope {
                try coordinatedCopy(source, to: target)
            } else {
                try copyContents(source, to: target)
            }
        } catch {
            try? FileManager.default.removeItem(at: target)
            throw error
        }
        return Self(id: id, url: target, name: inputName ?? source.lastPathComponent)
    }

    private static func coordinatedCopy(_ source: URL, to target: URL) throws {
        var coordinationError: NSError?
        var copyResult: Result<Void, Error>?
        NSFileCoordinator().coordinate(
            readingItemAt: source, options: [], error: &coordinationError
        ) { coordinatedURL in
            copyResult = Result { try copyContents(coordinatedURL, to: target) }
        }
        if let coordinationError { throw coordinationError }
        guard let copyResult else { throw CocoaError(.fileReadUnknown) }
        try copyResult.get()
    }

    private static func copyContents(_ source: URL, to target: URL) throws {
        let reader = try FileHandle(forReadingFrom: source)
        defer { try? reader.close() }
        guard FileManager.default.createFile(atPath: target.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let writer = try FileHandle(forWritingTo: target)
        defer { try? writer.close() }
        var totalBytes = 0
        while let data = try reader.read(upToCount: 64 * 1024), !data.isEmpty {
            totalBytes += data.count
            guard totalBytes <= parserSafetyMaximumInputBytes else {
                throw CocoaError(.fileReadTooLarge)
            }
            let values = try target.resourceValues(
                forKeys: [.volumeAvailableCapacityForImportantUsageKey]
            )
            if let available = values.volumeAvailableCapacityForImportantUsage,
               available < minimumFreeBytes + Int64(data.count) {
                throw CocoaError(.fileWriteOutOfSpace)
            }
            try writer.write(contentsOf: data)
        }
    }

}

private nonisolated final class ImportedInputOwnership: @unchecked Sendable {
    private let url: URL
    private let removeOnRelease: Bool

    init(url: URL, removeOnRelease: Bool) {
        self.url = url
        self.removeOnRelease = removeOnRelease
    }

    deinit {
        guard removeOnRelease else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
