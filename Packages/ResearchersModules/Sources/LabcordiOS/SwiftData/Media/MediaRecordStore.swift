import Foundation
import ImageIO
import LabcordShared
import SwiftData
import UniformTypeIdentifiers

@MainActor
final class MediaRecordStore {
    private enum MediaError: Error {
        case invalidPhotoData
        case invalidVideoFile
    }

    static let shared = MediaRecordStore()

    private let store = ExperimentStore.shared

    private init() {}

    func savePhoto(experimentID: UUID, id: UUID, recordedAt: Date, data: Data) throws {
        let fileExtension = try photoFileExtension(for: data)
        try saveMedia(
            experimentID: experimentID,
            id: id,
            recordedAt: recordedAt,
            type: .photo,
            directory: "Photos",
            fileExtension: fileExtension,
            installFile: { fileURL in
                try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            },
            rollbackFile: { fileURL in
                try? FileManager.default.removeItem(at: fileURL)
            }
        )
    }

    func saveVideo(experimentID: UUID, id: UUID, recordedAt: Date, sourceURL: URL) throws {
        try Task.checkCancellation()
        guard sourceURL.isFileURL, sourceURL.pathExtension.lowercased() == "mov" else {
            throw MediaError.invalidVideoFile
        }
        try saveMedia(
            experimentID: experimentID,
            id: id,
            recordedAt: recordedAt,
            type: .video,
            directory: "Videos",
            fileExtension: "mov",
            installFile: { fileURL in
                try Task.checkCancellation()
                try FileManager.default.moveItem(at: sourceURL, to: fileURL)
                try FileManager.default.setAttributes(
                    [.protectionKey: FileProtectionType.complete],
                    ofItemAtPath: fileURL.path
                )
            },
            rollbackFile: { fileURL in
                guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
                try? FileManager.default.moveItem(at: fileURL, to: sourceURL)
            }
        )
    }

    private func saveMedia(
        experimentID: UUID,
        id: UUID,
        recordedAt: Date,
        type: RecordType,
        directory: String,
        fileExtension: String,
        installFile: (URL) throws -> Void,
        rollbackFile: (URL) -> Void
    ) throws {
        let context = try store.makeContext()
        guard let experiment = try store.find(id: experimentID, in: context) else {
            throw ExperimentStore.StoreError.experimentNotFound
        }
        guard !experiment.records.contains(where: { $0.id == id }) else { return }

        let relativePath = "\(directory)/\(experimentID.uuidString)/"
            + "\(id.uuidString).\(fileExtension)"
        let fileURL = URL.applicationSupportDirectory.appending(path: relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )

        do {
            try installFile(fileURL)
            experiment.records.append(
                ExperimentRecord(
                    id: id,
                    type: type,
                    recordedAt: recordedAt,
                    note: "",
                    filePath: relativePath
                )
            )
            try context.save()
        } catch {
            rollbackFile(fileURL)
            throw error
        }
    }

    func cancelVideoSave(experimentID: UUID, id: UUID, sourceURL: URL) throws {
        var cleanupError: Error?
        do {
            let context = try store.makeContext()
            if let experiment = try store.find(id: experimentID, in: context),
               let record = experiment.records.first(where: { $0.id == id && $0.type == .video }) {
                experiment.records.removeAll { $0.id == record.id }
                context.delete(record)
                try context.save()
            }

            let savedURL = URL.applicationSupportDirectory
                .appending(path: "Videos/\(experimentID.uuidString)/\(id.uuidString).mov")
            try removeExistingFile(at: savedURL)
        } catch {
            cleanupError = error
        }

        do {
            try removeExistingFile(at: sourceURL)
        } catch {
            if cleanupError == nil { cleanupError = error }
        }
        if let cleanupError { throw cleanupError }
    }

    func removeFiles(experimentID: UUID) throws {
        let photoDirectory = URL.applicationSupportDirectory
            .appending(path: "Photos/\(experimentID.uuidString)")
        let videoDirectory = URL.applicationSupportDirectory
            .appending(path: "Videos/\(experimentID.uuidString)")
        try removeExistingFile(at: photoDirectory)
        try removeExistingFile(at: videoDirectory)
    }

    private func removeExistingFile(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private func photoFileExtension(for data: Data) throws -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw MediaError.invalidPhotoData
        }
        return try photoFileExtension(for: source)
    }

    private func photoFileExtension(for source: CGImageSource) throws -> String {
        guard let typeIdentifier = CGImageSourceGetType(source),
              let imageType = UTType(typeIdentifier as String),
              imageType.conforms(to: .image),
              let fileExtension = imageType.preferredFilenameExtension else {
            throw MediaError.invalidPhotoData
        }
        return fileExtension
    }

    func repairPhotoFileExtensions(
        in experiment: Experiment,
        context: ModelContext
    ) throws {
        let fileManager = FileManager.default
        var movedFiles: [(original: URL, updated: URL)] = []

        for record in experiment.records where record.type == .photo {
            guard let path = record.filePath else { continue }
            let originalURL = URL.applicationSupportDirectory.appending(path: path)
            guard let source = CGImageSourceCreateWithURL(originalURL as CFURL, nil),
                  let fileExtension = try? photoFileExtension(for: source),
                  originalURL.pathExtension.lowercased() != fileExtension else { continue }
            let updatedURL = originalURL.deletingPathExtension()
                .appendingPathExtension(fileExtension)
            do {
                try fileManager.moveItem(at: originalURL, to: updatedURL)
                record.filePath = "Photos/\(experiment.id.uuidString)/"
                    + "\(record.id.uuidString).\(fileExtension)"
                movedFiles.append((original: originalURL, updated: updatedURL))
            } catch {
                continue
            }
        }

        guard !movedFiles.isEmpty else { return }
        do {
            try context.save()
        } catch {
            for move in movedFiles.reversed() {
                try? fileManager.moveItem(at: move.updated, to: move.original)
            }
            throw error
        }
    }
}
