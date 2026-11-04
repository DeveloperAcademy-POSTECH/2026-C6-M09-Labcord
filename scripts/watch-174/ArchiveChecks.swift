import Foundation

@main
struct ArchiveChecks {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let sender = WatchAudioArchive(root: root.appendingPathComponent("watch"))
        let receiverRoot = root.appendingPathComponent("phone")
        let receiver = WatchAudioArchive(root: receiverRoot)
        let header = WatchAudioHeader(
            experimentID: UUID(), recordingID: UUID(), startedAt: .now, sampleRate: 16_000
        )
        let first = WatchAudioChunk(
            header: header, sequence: 0, firstSample: 0, pcm: Data([1, 0])
        )
        let second = WatchAudioChunk(
            header: header, sequence: 1, firstSample: 1, pcm: Data([2, 0])
        )
        let manifest = WatchAudioManifest(header: header, chunkCount: 2, totalSamples: 2)
        _ = try await sender.accept(first)
        _ = try await sender.accept(second)
        _ = try await sender.finish(manifest)
        _ = try await receiver.finish(manifest)
        _ = try await receiver.accept(second)
        do {
            _ = try await receiver.completeManifest(header)
            fatalError("missing chunk was accepted")
        } catch WatchAudioError.incomplete {}
        let duplicate = try await receiver.accept(second)
        precondition(duplicate.receivedSequences == [1])
        let conflict = WatchAudioChunk(
            header: header, sequence: 1, firstSample: 1, pcm: Data([3, 0])
        )
        do {
            _ = try await receiver.accept(conflict)
            fatalError("conflicting retransmission was accepted")
        } catch WatchAudioError.conflict {}
        _ = try await receiver.accept(first)
        let restarted = WatchAudioArchive(root: receiverRoot)
        let complete = try await restarted.completeManifest(header)
        precondition(complete == manifest)
        let receipt = try await restarted.status(header)
        do {
            try await sender.acknowledgeSaved(receipt)
            fatalError("chunk ACK was treated as save ACK")
        } catch WatchAudioError.incomplete {}
        try await checkFinalACK(sender, receiver: restarted, header: header, first: first)
        try await checkQuota(root: root)
        try await checkInvalidChunks(restarted, header: header, first: first)
        try await checkInterruptedAndCancellation(root: root)
        print("PASS: recovery, integrity, ACK loss, quota, retention and codec checks")
    }

    static func checkFinalACK(
        _ sender: WatchAudioArchive, receiver: WatchAudioArchive,
        header: WatchAudioHeader, first: WatchAudioChunk
    ) async throws {
        let saved = try await receiver.markSaved(header, recordID: header.recordingID)
        try await sender.acknowledgeSaved(saved)
        try await sender.acknowledgeSaved(saved)
        let preserved = try await sender.chunk(header, 0)
        precondition(preserved == first)
    }

    static func checkQuota(root: URL) async throws {
        let header = WatchAudioHeader(
            experimentID: UUID(), recordingID: UUID(), startedAt: .now, sampleRate: 16_000
        )
        let tooSmall = WatchAudioArchive(
            root: root.appendingPathComponent("full"), maximumBytes: 1
        )
        do {
            try await tooSmall.begin(header)
            fatalError("storage limit was ignored")
        } catch WatchAudioError.storageFull {}
    }

    static func checkInvalidChunks(
        _ restarted: WatchAudioArchive, header: WatchAudioHeader, first: WatchAudioChunk
    ) async throws {
        let overlap = WatchAudioChunk(
            header: header, sequence: 2, firstSample: 0, pcm: Data([4, 0])
        )
        do {
            _ = try await restarted.accept(overlap)
            fatalError("out of manifest range was accepted")
        } catch WatchAudioError.conflict {}
        let malformed = WatchAudioChunk(
            header: header, sequence: 3, firstSample: 2, pcm: Data([1])
        )
        precondition(!malformed.isValid)
        let roundTrip = try JSONDecoder().decode(
            WatchAudioMessage.self, from: JSONEncoder().encode(WatchAudioMessage.chunk(first))
        )
        precondition(roundTrip == .chunk(first))
    }

    static func checkInterruptedAndCancellation(root: URL) async throws {
        let archive = WatchAudioArchive(root: root.appendingPathComponent("interrupted"))
        let header = WatchAudioHeader(
            experimentID: UUID(), recordingID: UUID(), startedAt: .now, sampleRate: 48_000
        )
        let chunk = WatchAudioChunk(header: header, sequence: 0, firstSample: 0, pcm: Data([1, 0]))
        _ = try await archive.accept(chunk)
        let interrupted = try await archive.sealInterrupted(header)
        precondition(interrupted.manifest?.interrupted == true)
        try await archive.rememberRemoteReceipt(interrupted)
        let remote = try await archive.remoteReceipt(header)
        precondition(remote == interrupted)
        let cancelled = try await archive.cancel(header)
        precondition(cancelled.isCancelled)
        do {
            _ = try await archive.markSaved(header, recordID: header.recordingID)
            fatalError("cancelled recording was marked saved")
        } catch WatchAudioError.conflict {}
        let original = try await archive.chunk(header, 0)
        precondition(original == chunk)
        let foreignHeader = WatchAudioHeader(
            experimentID: UUID(), recordingID: header.recordingID,
            startedAt: header.startedAt, sampleRate: header.sampleRate
        )
        do {
            _ = try await archive.status(foreignHeader)
            fatalError("recording was mixed with a different experiment")
        } catch WatchAudioError.conflict {}
    }
}
