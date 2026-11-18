#if DEBUG
import ComposableArchitecture
import Foundation
import LabcordiOS
import LabcordShared
import UIKit

@MainActor
struct RecordingDemoSeeder {
    @Dependency(\.experimentClient) private var experiments

    static let experimentID = UUID(uuidString: "D3A00000-0000-4000-8000-000000000001")!

    private enum Kind: String, CaseIterable, Decodable {
        case photo
        case audio
        case video
    }

    private struct Record: Decodable {
        let id: UUID
        let kind: Kind
        let file: String
        let offsetSeconds: TimeInterval
        let note: String
        let transcript: String?
        let previousNote: String?
        let previousTranscript: String?

        var isValid: Bool {
            guard file.hasPrefix("LabcordDemo-"), file == (file as NSString).lastPathComponent,
                  note.count <= 300 else { return false }
            switch kind {
            case .photo:
                return file.hasSuffix(".jpg") && !note.trimmingCharacters(in: .whitespaces).isEmpty
            case .audio:
                return file.hasSuffix(".caf") && transcript?.isEmpty == false
            case .video:
                return file.hasSuffix(".mov") && !note.trimmingCharacters(in: .whitespaces).isEmpty
            }
        }
    }

    static let replacementIDs = (101...104).map {
        UUID(uuidString: String(format: "D3A00000-0000-4000-8000-%012d", $0))!
    }

    static var hasReplacement: Bool { manifestAsset != nil }

    private static var manifestAsset: NSDataAsset? {
        NSDataAsset(name: "LabcordDemo-manifest")
    }

    static func owns(_ id: UUID) -> Bool {
        id == experimentID || replacementIDs.contains(id)
    }

    static func isVisible(_ id: UUID, includesDemo: Bool) -> Bool {
        includesDemo || !owns(id)
    }

    private struct Manifest: Decodable {
        let experiments: [Fixture]
    }

    private struct Fixture: Decodable {
        let id: UUID
        let title: String
        let startedAt: Date
        let completedAt: Date
        let `protocol`: ExperimentProtocol
        let records: [Record]
    }

    private enum SeedError: LocalizedError {
        case invalidManifest
        case missingMedia(String)
        case incompleteResult

        var errorDescription: String? {
            switch self {
            case .invalidManifest: "데모 실험 파일 구성이 올바르지 않습니다."
            case let .missingMedia(file): "데모 미디어를 읽을 수 없습니다. \(file)"
            case .incompleteResult: "데모 실험 결과를 저장하지 못했습니다."
            }
        }
    }

    func install() async throws {
        let fixtures = try loadFixtures()
        let sources = try fixtures.map { try $0.records.map(source(for:)) }

        for (fixture, files) in zip(fixtures, sources) {
            try install(fixture, sources: files)
        }
    }

    private func install(_ fixture: Fixture, sources: [Data]) throws {
        let existing = try experiments.loadResultDetail(fixture.id)
        if let existing, !isRecoverableSeed(existing, for: fixture) {
            try updateDemoText(in: existing, from: fixture)
            return
        }

        // 최초 설치는 모든 미디어를 저장할 때까지 실험을 준비 상태로 유지합니다.
        _ = try create(fixture)
        for (record, source) in zip(fixture.records, sources) {
            try installRecord(
                record, source: source, in: fixture,
                existing: existing?.records.first { $0.id == record.id }
            )
        }
        guard let result = try experiments.loadResultDetail(fixture.id),
              hasAllDemoMedia(in: result, for: fixture)
        else { throw SeedError.incompleteResult }
        try experiments.complete(fixture.id, fixture.completedAt)
    }

    private func isRecoverableSeed(
        _ result: ExperimentResultDetail, for fixture: Fixture
    ) -> Bool {
        guard result.status == .ready, result.mode == .procedure,
              result.title == fixture.title,
              result.createdAt == fixture.startedAt, result.startedAt == nil,
              result.endedAt.isEmpty, result.pauses.isEmpty, result.statusHistory.count == 1,
              result.statusHistory.first?.status == .ready,
              let stored = result.procedure
        else { return false }
        let expected = fixture.protocol
        guard stored.timerSeconds == expected.timerSeconds,
              stored.materials == expected.materials, stored.samples == expected.samples,
              stored.glossaryTerms == expected.glossaryTerms, stored.units == expected.units
        else { return false }
        return result.records.allSatisfy { saved in
            guard let record = fixture.records.first(where: { $0.id == saved.id }),
                  saved.type.rawValue == record.kind.rawValue else { return false }
            return saved.recordedAt == fixture.startedAt.addingTimeInterval(record.offsetSeconds)
        }
    }

    private func installRecord(
        _ record: Record, source: Data, in fixture: Fixture,
        existing: ExperimentResultDetail.Record?
    ) throws {
        if let existing {
            // 중단 시 기록과 미디어만 있고 메모는 아직 저장되지 않았을 수 있습니다.
            guard existing.note.isEmpty else { return }
        } else {
            try save(record, from: source, in: fixture)
        }
        _ = try experiments.updateRecordContent(fixture.id, record.id, record.note, nil, nil)
    }

    private func loadFixtures() throws -> [Fixture] {
        guard let manifest = Self.manifestAsset else { throw SeedError.invalidManifest }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let fixtures = try decoder.decode(Manifest.self, from: manifest.data)
            .experiments
        let recordIDs = fixtures.flatMap { $0.records.map(\.id) }
        guard fixtures.count == Self.replacementIDs.count,
              Set(fixtures.map(\.id)) == Set(Self.replacementIDs),
              Set(fixtures.map(\.title)).count == fixtures.count,
              Set(recordIDs).count == recordIDs.count,
              Set(recordIDs).isDisjoint(with: [Self.experimentID] + Self.replacementIDs),
              fixtures.allSatisfy(Self.isValid)
        else { throw SeedError.invalidManifest }
        return fixtures
    }

    private static func isValid(_ fixture: Fixture) -> Bool {
        let records = fixture.records
        let offsets = records.map(\.offsetSeconds)
        let duration = fixture.completedAt.timeIntervalSince(fixture.startedAt)
        return fixture.title.hasPrefix("데모 - ")
            && duration > 0
            && (10...15).contains(records.count)
            && Set(records.map(\.kind)) == Set(Kind.allCases)
            && Set(offsets).count == offsets.count
            && offsets == offsets.sorted()
            && offsets.allSatisfy { 0 <= $0 && $0 <= duration }
            && records.allSatisfy(\.isValid)
    }

    private func source(for record: Record) throws -> Data {
        let name = (record.file as NSString).deletingPathExtension
        guard let asset = NSDataAsset(name: name), !asset.data.isEmpty
        else { throw SeedError.missingMedia(record.file) }
        return asset.data
    }

    private func create(_ fixture: Fixture) throws -> ExperimentListEntry {
        try experiments.createWithProtocol(
            fixture.id, fixture.startedAt, fixture.title, fixture.protocol
        )
    }

    private func hasAllDemoMedia(
        in result: ExperimentResultDetail, for fixture: Fixture
    ) -> Bool {
        fixture.records.allSatisfy { record in
            guard let saved = result.records.first(where: { $0.id == record.id }),
                  saved.type.rawValue == record.kind.rawValue,
                  let path = saved.filePath else { return false }
            return FileManager.default.isReadableFile(
                atPath: URL.applicationSupportDirectory.appending(path: path).path
            )
        }
    }

    private func updateDemoText(in result: ExperimentResultDetail, from fixture: Fixture) throws {
        for record in fixture.records {
            guard let saved = result.records.first(where: { $0.id == record.id }) else { continue }
            let note = saved.note == record.previousNote ? record.note : saved.note
            let matchesPriorTranscript = saved.transcript == record.previousTranscript
            let transcript = matchesPriorTranscript ? record.transcript : nil
            guard note != saved.note || (transcript != nil && transcript != saved.transcript)
            else { continue }
            _ = try experiments.updateRecordContent(fixture.id, record.id, note, transcript, nil)
        }
    }

    private func save(_ record: Record, from source: Data, in fixture: Fixture) throws {
        let id = fixture.id
        let date = fixture.startedAt.addingTimeInterval(record.offsetSeconds)
        if record.kind == .photo {
            try experiments.savePhoto(id, record.id, date, source)
            return
        }

        let fileExtension = (record.file as NSString).pathExtension
        let copy = FileManager.default.temporaryDirectory
            .appending(path: "labcord-demo-\(UUID().uuidString).\(fileExtension)")
        defer { try? FileManager.default.removeItem(at: copy) }
        try source.write(to: copy, options: .atomic)

        if record.kind == .video {
            try removeOrphanVideo(recordID: record.id, experimentID: id, matching: copy)
            try experiments.saveVideo(id, record.id, date, copy)
        } else {
            try experiments.saveAudio(id, record.id, date, copy, record.transcript ?? "")
        }
    }

    private func removeOrphanVideo(
        recordID: UUID, experimentID: UUID, matching source: URL
    ) throws {
        let destination = URL.applicationSupportDirectory
            .appending(path: "Videos/\(experimentID.uuidString)/\(recordID.uuidString).mov")
        let files = FileManager.default
        guard files.fileExists(atPath: destination.path) else { return }
        // SwiftData 저장 전에 옮겨진 동일한 영상만 다시 설치합니다.
        guard files.contentsEqual(atPath: destination.path, andPath: source.path) else {
            throw SeedError.incompleteResult
        }
        try files.removeItem(at: destination)
    }
}
#endif
