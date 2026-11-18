#if DEBUG && targetEnvironment(simulator)
import AVFoundation
import Foundation
import LabcordShared

enum RecordingDemoSpeechScene: Sendable {
    case phone
    case watch

    init?(fileName: String) {
        switch fileName.uppercased() {
        case "V03.MP4": self = .phone
        case "V06-A.MP4", "V06-A-PLUS-B.MP4", "W02_DOUBLE_PINCH.MP4": self = .watch
        default: return nil
        }
    }

    var phraseIndex: Int { self == .phone ? 0 : 1 }

    var transcriptFrames: [Int] {
        self == .phone ? [77, 191, 269] : []
    }

    func visibleSegmentCount(at seconds: Double) -> Int {
        guard seconds.isFinite, seconds >= 0 else { return 0 }
        return transcriptFrames.prefix { seconds >= Double($0) / 24 }.count
    }
}

struct RecordingDemoSpeechPlayback: Sendable {
    let selectionID: UUID
    let playbackID: UUID
    let scene: RecordingDemoSpeechScene
    let seconds: Double

    func matches(_ other: Self) -> Bool {
        selectionID == other.selectionID && playbackID == other.playbackID && scene == other.scene
    }
}

/// Records microphone audio while displaying scripted demo text, without speech recognition.
actor RecordingDemoSpeechSession {
    private let phrases: [[String]] = [
        ["A01, pH 4.04 확인.", "지시약 두 방울을 넣고 혼합했습니다.",
         "주황색이며 침전은 보이지 않습니다."],
        ["A01, 5분 경과.", "색상 변화 없이 주황색을 유지하고 있습니다."],
        ["A01, 15분 관찰 완료.", "주황색이 유지되고 침전은 관찰되지 않았습니다."]
    ]
    private var nextPhrase = 0
    private var experimentID: UUID?
    private var attemptPhrase: Int?
    private var recorder: AVAudioRecorder?
    private var audioURL: URL?
    private var recordingID: UUID?
    private var transcript = ""
    private var deferredTranscript: String?
    private var continuation: AsyncStream<SpeechRecordingEvent>.Continuation?
    private var displayTask: Task<Void, Never>?
    private var pendingStartID: UUID?

    func start(experimentID: UUID) async throws -> AsyncStream<SpeechRecordingEvent> {
        guard recordingID == nil, pendingStartID == nil else {
            throw SpeechRecordingError.alreadyRecording
        }
        guard AVAudioApplication.shared.recordPermission == .granted else {
            throw PermissionAccessError(.microphone)
        }
        let startID = UUID()
        pendingStartID = startID
        let playback = await RecordingDemoVideoPreview.speechPlayback()
        guard pendingStartID == startID else { throw CancellationError() }
        defer { if pendingStartID == startID { pendingStartID = nil } }
        try Task.checkCancellation()
        let id = UUID()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("demo-\(id).caf")
        if self.experimentID != experimentID {
            self.experimentID = experimentID
            nextPhrase = 0
        }
        let phraseIndex = playback?.scene.phraseIndex ?? nextPhrase % phrases.count
        try startRecorder(at: url, phraseIndex: phraseIndex)
        audioURL = url
        recordingID = id
        transcript = ""
        attemptPhrase = playback == nil ? nextPhrase : nil
        let segments = phrases[phraseIndex]
        if playback == nil { nextPhrase += 1 }
        let stream = AsyncStream<SpeechRecordingEvent> { continuation in
            self.continuation = continuation
        }
        deferredTranscript = playback?.scene == .watch ? segments.joined(separator: " ") : nil
        if deferredTranscript == nil {
            startDisplaying(segments, playback: playback, recordingID: id)
        }
        return stream
    }

    private func startRecorder(at url: URL, phraseIndex: Int) throws {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord, mode: .measurement, options: [.defaultToSpeaker]
            )
            try session.setActive(true)
            let newRecorder = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false
            ])
            guard newRecorder.record() else { throw SpeechRecordingError.microphoneUnavailable }
            recorder = newRecorder
        } catch {
            try? FileManager.default.removeItem(at: url)
            let fixture = URL.documentsDirectory.appending(path: "LabcordDemoInput")
                .appending(path: "audio-\(phraseIndex + 1).caf")
            try FileManager.default.copyItem(at: fixture, to: url)
        }
    }

    private func startDisplaying(
        _ segments: [String], playback: RecordingDemoSpeechPlayback?, recordingID: UUID
    ) {
        displayTask = Task { [weak self] in
            if let playback {
                await self?.display(segments, playback: playback, recordingID: recordingID)
                return
            }
            for (index, segment) in segments.enumerated() {
                do { try await Task.sleep(for: .seconds(index == 0 ? 1 : 4)) } catch { return }
                guard let self,
                      await self.append(segment, recordingID: recordingID) else { return }
            }
        }
    }

    private func display(
        _ segments: [String], playback: RecordingDemoSpeechPlayback, recordingID: UUID
    ) async {
        var displayedCount = 0
        while !Task.isCancelled, displayedCount < segments.count {
            guard let current = await RecordingDemoVideoPreview.speechPlayback(),
                  playback.matches(current), self.recordingID == recordingID,
                  !Task.isCancelled else { return }
            let visibleCount = min(
                segments.count, current.scene.visibleSegmentCount(at: current.seconds)
            )
            while displayedCount < visibleCount {
                guard append(segments[displayedCount], recordingID: recordingID) else { return }
                displayedCount += 1
            }
            do { try await Task.sleep(for: .milliseconds(20)) } catch { return }
        }
    }

    private func append(_ segment: String, recordingID: UUID) -> Bool {
        guard self.recordingID == recordingID else { return false }
        transcript = [transcript, segment].filter { !$0.isEmpty }.joined(separator: " ")
        continuation?.yield(.transcript(transcript))
        return true
    }

    func stop() -> SpeechRecording? {
        guard let url = audioURL, let id = recordingID else {
            pendingStartID = nil
            return nil
        }
        recorder?.stop()
        let result = SpeechRecording(
            recordingID: id, audioURL: url, transcript: deferredTranscript ?? transcript
        )
        clear()
        return result
    }

    func cancel() {
        if recordingID != nil, let attemptPhrase { nextPhrase = attemptPhrase }
        recorder?.stop()
        if let url = audioURL { try? FileManager.default.removeItem(at: url) }
        clear()
    }

    private func clear() {
        pendingStartID = nil
        displayTask?.cancel()
        displayTask = nil
        continuation?.finish()
        continuation = nil
        recorder = nil
        audioURL = nil
        recordingID = nil
        transcript = ""
        deferredTranscript = nil
        attemptPhrase = nil
    }
}
#endif
