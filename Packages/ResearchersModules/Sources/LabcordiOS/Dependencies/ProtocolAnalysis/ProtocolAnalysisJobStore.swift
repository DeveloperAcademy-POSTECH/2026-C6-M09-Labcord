import Foundation

nonisolated struct ProtocolAnalysisJobStore: Sendable {
    let directory: URL

    func jobDirectory(_ id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func prepare(
        id: UUID, inputs: [ProtocolAnalysisJobInput], now: Date
    ) throws -> ProtocolAnalysisJobRecord {
        let target = jobDirectory(id)
        guard !FileManager.default.fileExists(atPath: target.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try protect(target)
        var stored: [ProtocolAnalysisJobRecord.Input] = []
        for input in inputs {
            let suffix = input.url.pathExtension
                .filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
            let fileName = input.id.uuidString + (suffix.isEmpty ? "" : "." + suffix)
            let url = target.appendingPathComponent(fileName)
            try FileManager.default.copyItem(at: input.url, to: url)
            try protect(url)
            stored.append(.init(
                id: input.id, fileName: fileName, name: input.name, isPhoto: input.isPhoto
            ))
        }
        var record = ProtocolAnalysisJobRecord(
            id: id, createdAt: now, updatedAt: now, status: .queued, inputs: stored
        )
        record.version = 2
        record.reviewPolicyVersion = ProtocolTermReviewCheckpoint.currentPolicyVersion
        try save(record)
        return record
    }

    func save(_ record: ProtocolAnalysisJobRecord) throws {
        let url = jobDirectory(record.id).appendingPathComponent("checkpoint.json")
        let data = try JSONEncoder().encode(record)
        try data.write(
            to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
        try protect(url)
    }

    func complete(_ record: ProtocolAnalysisJobRecord) throws -> ProtocolAnalysisJobRecord {
        var completed = record
        completed.status = .completed
        completed.message = nil
        completed.updatedAt = Date()
        try save(completed)
        return completed
    }

    func latest() throws -> ProtocolAnalysisJobRecord? {
        guard FileManager.default.fileExists(atPath: directory.path) else { return nil }
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        ).filter { UUID(uuidString: $0.lastPathComponent) != nil }
        let records = try urls.compactMap { url -> ProtocolAnalysisJobRecord? in
            let checkpoint = url.appendingPathComponent("checkpoint.json")
            guard FileManager.default.fileExists(atPath: checkpoint.path) else { return nil }
            let record = try JSONDecoder().decode(
                ProtocolAnalysisJobRecord.self, from: Data(contentsOf: checkpoint)
            )
            guard (1...2).contains(record.version),
                  record.id.uuidString == url.lastPathComponent else {
                throw CocoaError(.coderReadCorrupt)
            }
            try validateReviews(record)
            return record
        }
        let latest = records.max { $0.updatedAt < $1.updatedAt }
        return latest?.status == .cancelled ? nil : latest
    }

    private func validateReviews(_ record: ProtocolAnalysisJobRecord) throws {
        if let policy = record.reviewPolicyVersion {
            guard policy == ProtocolTermReviewCheckpoint.currentPolicyVersion else {
                throw CocoaError(.coderReadCorrupt)
            }
        } else if record.version == 2 || record.reviews?.isEmpty == false {
            throw CocoaError(.coderReadCorrupt)
        }
        for (key, review) in record.reviews ?? [:] {
            guard let terms = record.selected[key], let document = record.documents[key] else {
                throw CocoaError(.coderReadCorrupt)
            }
            try review.validate(terms: terms, source: document.restored().fullText)
        }
    }

    func inputs(_ record: ProtocolAnalysisJobRecord) throws -> [ProtocolAnalysisJobInput] {
        try record.inputs.map { item in
            guard !item.fileName.isEmpty, item.fileName != ".", item.fileName != "..",
                  item.fileName == (item.fileName as NSString).lastPathComponent else {
                throw CocoaError(.coderReadCorrupt)
            }
            return ProtocolAnalysisJobInput(
                id: item.id, url: jobDirectory(record.id).appendingPathComponent(item.fileName),
                name: item.name, isPhoto: item.isPhoto
            )
        }
    }

    private func protect(_ url: URL) throws {
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
}
