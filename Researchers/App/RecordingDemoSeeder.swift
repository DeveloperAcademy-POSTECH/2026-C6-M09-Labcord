#if DEBUG && targetEnvironment(simulator)
import AVFoundation
import ComposableArchitecture
import Foundation
import LabcordiOS
import LabcordShared
import UIKit

/// Explicitly imports a synthetic completed experiment for recording on a simulator.
@MainActor
struct RecordingDemoSeeder {
    static let argument = "-LabcordDemoSeedDirectory"
    private static var defaultDirectory: URL {
        URL.documentsDirectory.appending(path: "LabcordDemoInput", directoryHint: .isDirectory)
    }
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(argument)
            || FileManager.default.fileExists(atPath: defaultDirectory.path)
    }

    static func displayDate(_ date: Date, title: String) -> Date {
        guard title == "Labcord" else { return date }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        var components = calendar.dateComponents(
            [.hour, .minute, .second, .nanosecond], from: date
        )
        components.year = 2026
        components.month = 11
        components.day = 20
        return calendar.date(from: components) ?? date
    }

    @Dependency(\.experimentClient) private var experiments

    func resetSimulatorExperiments() throws {
        for experiment in try experiments.load() {
            try experiments.delete(experiment.id)
        }
        let support = URL.applicationSupportDirectory
        for name in [
            "Photos", "Videos", "Audio", "VoiceRecordingJournals",
            "IncompleteVoiceRecordings", "WatchAudioIncoming", "WatchAudioInbox"
        ] {
            let url = support.appending(path: name)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    static let experimentID = UUID(uuidString: "D3A00000-0000-4000-8000-000000000001")!
    private var experimentID: UUID { Self.experimentID }
    private let baseDate = Date(timeIntervalSince1970: 1_794_805_200)
    private let procedure = ExperimentProtocol(
        timerSeconds: [300, 900],
        materials: ["표준완충용액", "범용 pH 지시약"],
        samples: ["A01", "B01", "C01"],
        glossaryTerms: ["시연용 합성 데이터", "LC-CHEM-026"],
        units: ["pH", "mL"]
    )

    private enum Kind: String {
        case photo
        case audio
        case video
    }

    private struct Record {
        let id: UUID
        let kind: Kind
        let file: String
        let offset: TimeInterval
        let note: String
        let transcript: String?
    }

    private var records: [Record] {
        [
            makeRecord(1, .photo, "photo-1.jpg", 0,
                       "pH 4, 7, 10 시료 아홉 개 배치 완료."),
            makeRecord(2, .audio, "audio-1.caf", 5,
                       "A01 혼합 직후 관찰",
                       "A01, pH 4.04 확인. 지시약 두 방울을 넣고 혼합했습니다. "
                       + "주황색이며 침전은 보이지 않습니다."),
            makeRecord(3, .photo, "photo-2.jpg", 18,
                       "A01 혼합 직후. 주황색, 침전 없음."),
            makeRecord(4, .video, "video-1.jpg", 20,
                       "A01 지시약 첨가 및 혼합 장면."),
            makeRecord(5, .audio, "audio-2.caf", 309,
                       "A01 5분 관찰",
                       "A01, 5분 경과. 색상 변화 없이 주황색을 유지하고 있습니다."),
            makeRecord(6, .photo, "photo-3.jpg", 313,
                       "A01 5분 관찰. 색 변화 없음."),
            makeRecord(7, .audio, "audio-3.caf", 914,
                       "A01 15분 관찰",
                       "A01, 15분 관찰 완료. 주황색이 유지되고 침전은 관찰되지 않았습니다."),
            makeRecord(8, .video, "video-2.jpg", 918,
                       "A01 15분 종료 관찰 장면."),
            makeRecord(9, .photo, "photo-4.jpg", 925,
                       "A01, B01, C01의 주황·녹색·청색 비교.")
        ]
    }

    private func makeRecord(
        _ number: Int, _ kind: Kind, _ file: String, _ offset: TimeInterval,
        _ note: String, _ transcript: String? = nil
    ) -> Record {
        let identifier = String(format: "D3A00000-0000-4000-8001-%012d", number)
        return Record(id: UUID(uuidString: identifier)!, kind: kind, file: file,
                      offset: offset, note: note, transcript: transcript)
    }

    enum SeedError: LocalizedError {
        case missingDirectory
        case invalidMedia(String)
        case conflictingExperiment
        case conflictingRecord(String)
        case missingRecord(String)

        var errorDescription: String? {
            switch self {
            case .missingDirectory: "시연 데이터 폴더가 지정되지 않았습니다."
            case let .invalidMedia(file): "시연 미디어를 읽거나 재생할 수 없습니다: \(file)"
            case .conflictingExperiment: "시연 실험 식별자가 다른 실험과 충돌합니다."
            case let .conflictingRecord(file): "시연 기록 식별자가 다른 기록과 충돌합니다: \(file)"
            case let .missingRecord(file): "저장된 시연 기록을 확인할 수 없습니다: \(file)"
            }
        }
    }

    func runIfRequested() async throws {
        let arguments = ProcessInfo.processInfo.arguments
        let directory: URL
        if let argumentIndex = arguments.firstIndex(of: Self.argument) {
            guard argumentIndex + 1 < arguments.count else { throw SeedError.missingDirectory }
            directory = URL(fileURLWithPath: arguments[argumentIndex + 1], isDirectory: true)
        } else {
            guard Self.isRequested else { return }
            directory = Self.defaultDirectory
        }
        try await validateMedia(in: directory)
        _ = try experiments.createWithProtocol(experimentID, baseDate, "Labcord", procedure)
        try verifyExistingExperiment()
        for record in records {
            try await importRecord(record, from: directory)
        }
        guard let result = try experiments.loadResultDetail(experimentID),
              records.allSatisfy({ expected in result.records.contains { $0.id == expected.id } })
        else { throw SeedError.conflictingExperiment }
        if result.status != .completed {
            try experiments.complete(experimentID, baseDate.addingTimeInterval(930))
        }
        print("Labcord demo import complete: \(experimentID.uuidString)")
    }

    private func validateMedia(in directory: URL) async throws {
        for record in records {
            let url = directory.appendingPathComponent(record.file)
            guard FileManager.default.isReadableFile(atPath: url.path) else {
                throw SeedError.invalidMedia(record.file)
            }
            if record.kind != .audio {
                guard let image = UIImage(contentsOfFile: url.path), image.cgImage != nil else {
                    throw SeedError.invalidMedia(record.file)
                }
            } else {
                let asset = AVURLAsset(url: url)
                let tracks = try await asset.loadTracks(withMediaType: .audio)
                let duration = try await asset.load(.duration)
                guard try await asset.load(.isPlayable), !tracks.isEmpty,
                      duration.seconds.isFinite, duration.seconds > 0 else {
                    throw SeedError.invalidMedia(record.file)
                }
            }
        }
    }

    private func verifyExistingExperiment() throws {
        guard let result = try experiments.loadResultDetail(experimentID) else { return }
        guard result.title == "Labcord", result.mode == .procedure,
              result.procedure?.glossaryTerms.contains("시연용 합성 데이터") == true,
              result.procedure?.glossaryTerms.contains("LC-CHEM-026") == true else {
            throw SeedError.conflictingExperiment
        }
        for record in records {
            guard let existing = result.records.first(where: { $0.id == record.id }) else {
                continue
            }
            guard existing.type.rawValue == record.kind.rawValue,
                  let path = existing.filePath,
                  FileManager.default.fileExists(
                    atPath: URL.applicationSupportDirectory.appending(path: path).path
                  ) else { throw SeedError.conflictingRecord(record.file) }
        }
    }

    private func importRecord(_ record: Record, from directory: URL) async throws {
        let current = try experiments.loadResultDetail(experimentID)
        if current?.records.contains(where: { $0.id == record.id }) == true { return }
        let source = directory.appendingPathComponent(record.file)
        let date = baseDate.addingTimeInterval(record.offset)
        switch record.kind {
        case .photo:
            try experiments.savePhoto(experimentID, record.id, date, Data(contentsOf: source))
        case .audio:
            try experiments.saveAudio(
                experimentID, record.id, date, source, record.transcript ?? ""
            )
        case .video:
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent("labcord-demo-\(UUID().uuidString).mov")
            defer { try? FileManager.default.removeItem(at: copy) }
            try await writeStillVideo(from: source, to: copy)
            try experiments.saveVideo(experimentID, record.id, date, copy)
        }
        guard try experiments.loadResultDetail(experimentID)?.records.contains(where: {
            $0.id == record.id
        }) == true else { throw SeedError.missingRecord(record.file) }
        _ = try experiments.updateRecordContent(experimentID, record.id, record.note, nil, nil)
    }
}

private extension RecordingDemoSeeder {
    func writeStillVideo(from source: URL, to destination: URL) async throws {
        let size = CGSize(width: 720, height: 1280)
        let buffer = try makeImageBuffer(from: source, size: size)
        try await encodeStillVideo(buffer: buffer, size: size, source: source, to: destination)
    }

    private func makeImageBuffer(from source: URL, size: CGSize) throws -> CVPixelBuffer {
        guard let image = UIImage(contentsOfFile: source.path) else {
            throw SeedError.invalidMedia(source.lastPathComponent)
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let normalized = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let scale = max(size.width / image.size.width, size.height / image.size.height)
            let scaledSize = CGSize(
                width: image.size.width * scale, height: image.size.height * scale
            )
            image.draw(in: CGRect(
                x: (size.width - scaledSize.width) / 2,
                y: (size.height - scaledSize.height) / 2,
                width: scaledSize.width, height: scaledSize.height
            ))
        }
        guard let cgImage = normalized.cgImage else {
            throw SeedError.invalidMedia(source.lastPathComponent)
        }
        return try makePixelBuffer(image: cgImage, size: size)
    }

    private func encodeStillVideo(
        buffer: CVPixelBuffer, size: CGSize, source: URL, to destination: URL
    ) async throws {
        let writer = try AVAssetWriter(outputURL: destination, fileType: .mov)
        defer { if writer.status == .writing { writer.cancelWriting() } }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height)
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input)
        guard writer.canAdd(input) else { throw SeedError.invalidMedia(source.lastPathComponent) }
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? SeedError.invalidMedia(source.lastPathComponent)
        }
        writer.startSession(atSourceTime: .zero)
        for time in [0.0, 2.966] {
            while !input.isReadyForMoreMediaData {
                try Task.checkCancellation()
                guard writer.status == .writing else {
                    throw writer.error ?? SeedError.invalidMedia(source.lastPathComponent)
                }
                try await Task.sleep(for: .milliseconds(20))
            }
            guard adaptor.append(buffer, withPresentationTime: CMTime(
                seconds: time, preferredTimescale: 600
            )) else { throw writer.error ?? SeedError.invalidMedia(source.lastPathComponent) }
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(seconds: 3, preferredTimescale: 600))
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw writer.error ?? SeedError.invalidMedia(source.lastPathComponent)
        }
        let asset = AVURLAsset(url: destination)
        guard try await asset.load(.isPlayable),
              !(try await asset.loadTracks(withMediaType: .video)).isEmpty,
              (try await asset.load(.duration)).seconds > 0 else {
            throw SeedError.invalidMedia(source.lastPathComponent)
        }
    }

    private func makePixelBuffer(image: CGImage, size: CGSize) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let result = CVPixelBufferCreate(
            kCFAllocatorDefault, Int(size.width), Int(size.height),
            kCVPixelFormatType_32BGRA, nil, &buffer
        )
        guard result == kCVReturnSuccess, let buffer else {
            throw SeedError.invalidMedia("pixel buffer")
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { throw SeedError.invalidMedia("pixel context") }
        context.draw(image, in: CGRect(origin: .zero, size: size))
        return buffer
    }
}
#endif
