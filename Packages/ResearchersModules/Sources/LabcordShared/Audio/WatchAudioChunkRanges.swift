import Foundation

struct WatchAudioChunkRanges {
    struct Range {
        let header: WatchAudioHeader
        let fileNumber: UInt64
        let modifiedAt: Date
        let size: Int
        let firstSample: Int64
        let endSample: Int64
    }

    private var recordingID: UUID?
    private var known: [URL: Range] = [:]

    mutating func range(
        for header: WatchAudioHeader, at url: URL, load: () throws -> WatchAudioChunk
    ) throws -> Range {
        selectRecording(header.recordingID)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        if let range = known[url], range.header == header,
           range.fileNumber == (attributes[.systemFileNumber] as? NSNumber)?.uint64Value,
           range.modifiedAt == attributes[.modificationDate] as? Date,
           range.size == (attributes[.size] as? NSNumber)?.intValue {
            return range
        }
        let value = try load()
        let range = makeRange(value, from: attributes)
        known[url] = range
        return range
    }

    mutating func remember(_ chunk: WatchAudioChunk, at url: URL) {
        selectRecording(chunk.header.recordingID)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        else { return }
        known[url] = makeRange(chunk, from: attributes)
    }

    mutating func remove(_ url: URL) {
        known.removeValue(forKey: url)
    }

    private mutating func selectRecording(_ id: UUID) {
        guard recordingID != id else { return }
        recordingID = id
        known.removeAll(keepingCapacity: true)
    }

    private func makeRange(
        _ chunk: WatchAudioChunk, from attributes: [FileAttributeKey: Any]
    ) -> Range {
        Range(
            header: chunk.header,
            fileNumber: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0,
            modifiedAt: attributes[.modificationDate] as? Date ?? .distantPast,
            size: (attributes[.size] as? NSNumber)?.intValue ?? 0,
            firstSample: chunk.firstSample,
            endSample: chunk.firstSample + chunk.sampleCount
        )
    }
}
