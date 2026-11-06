import AVFoundation
import Foundation
import Speech

final class SpeechRecognitionInput: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    init(_ request: SFSpeechAudioBufferRecognitionRequest) {
        self.request = request
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        request?.append(buffer)
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        request = nil
    }

    func replace(_ request: SFSpeechAudioBufferRecognitionRequest) {
        lock.lock()
        defer { lock.unlock() }
        self.request = request
    }
}

@MainActor
public final class SpeechRecordingSession {
    let audioEngine = AVAudioEngine()
    let audioSessionQueue = DispatchQueue(label: "com.researchers.speech.audio-session")
    let locale: Locale

    var startupID: UUID?
    var recordingID: UUID?
    var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    var recognitionInput: SpeechRecognitionInput?
    var recognitionTask: SFSpeechRecognitionTask?
    var eventContinuation: AsyncStream<SpeechRecordingEvent>.Continuation?
    var stopContinuations: [CheckedContinuation<SpeechRecording?, Never>] = []
    var stopTimeout: Task<Void, Never>?
    var recordingURL: URL?
    var recordingFile: AVAudioFile?
    var latestRecording: SpeechRecording?
    var latestRecordingIsRecovery = false
    var hasInputTap = false
    var audioActivationPending = false
    var ownsAudioSession = false
    var transcript = ""
    var recognitionEnded = false
    var transcriptionIncomplete = false
    var experimentID: UUID?
    var recognizer: SFSpeechRecognizer?
    var contextualStrings: [String] = []
    var recognitionGeneration = 0
    var committedTranscript = ""
    var recognitionRestarts = 0
    var audioInterruptionObserver: NSObjectProtocol?

    public init(locale: Locale = Locale(identifier: "ko-KR")) {
        self.locale = locale
    }

    public func start(
        experimentID: UUID, contextualStrings: [String] = []
    ) async throws -> AsyncStream<SpeechRecordingEvent> {
        guard startupID == nil, recordingID == nil else {
            throw SpeechRecordingError.alreadyRecording
        }
        discardLatestRecording()
        self.experimentID = experimentID

        let id = UUID()
        startupID = id
        defer { if startupID == id { startupID = nil } }

        recognizer = try authorizedRecognizer()
        guard let recognizer else { throw SpeechRecordingError.recognizerUnavailable }
        self.contextualStrings = contextualStrings
        try await activateForStartup(id)

        do {
            return try beginRecording(id: id, recognizer: recognizer)
        } catch {
            finishRecording(keepingFile: false)
            discardLatestRecording()
            throw error
        }
    }

    func beginRecording(
        id: UUID,
        recognizer: SFSpeechRecognizer
    ) throws -> AsyncStream<SpeechRecordingEvent> {
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { throw SpeechRecordingError.microphoneUnavailable }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("speech-\(id.uuidString).caf")
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        recordingURL = url
        recordingFile = file

        let request = makeRecognitionRequest()
        recognitionRequest = request
        let input = SpeechRecognitionInput(request)
        recognitionInput = input
        recordingID = id
        transcript = ""
        committedTranscript = ""
        recognitionRestarts = 0
        recognitionEnded = false
        transcriptionIncomplete = false
        if let experimentID {
            VoiceRecordingJournal.write(VoiceRecordingJournal.Entry(
                experimentID: experimentID, recordingID: id,
                filePath: url.path, startedAt: Date()
            ))
        }

        let (stream, continuation) = AsyncStream<SpeechRecordingEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        eventContinuation = continuation
        startRecognitionTask(id: id, recognizer: recognizer, request: request)

        installInputTap(on: inputNode, format: format, input: input, file: file, id: id)
        audioEngine.prepare()
        try audioEngine.start()
        observeAudioInterruptions(recordingID: id)
        try Task.checkCancellation()
        guard recordingID == id else { throw SpeechRecordingError.recognizerUnavailable }
        return stream
    }

    func installInputTap(
        on inputNode: AVAudioInputNode,
        format: AVAudioFormat,
        input: SpeechRecognitionInput,
        file: AVAudioFile,
        id: UUID
    ) {
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            input.append(buffer)
            do {
                try file.write(from: buffer)
            } catch {
                Task { @MainActor in
                    self?.fail(error, recordingID: id)
                }
            }
        }
        hasInputTap = true
    }

    public func stop() async -> SpeechRecording? {
        guard let id = recordingID else { return latestRecording }

        return await withCheckedContinuation { continuation in
            let isFirstStop = stopContinuations.isEmpty
            stopContinuations.append(continuation)
            guard isFirstStop else { return }
            stopInput()
            if recognitionEnded {
                finishRecording(keepingFile: true)
                return
            }
            recognitionRequest?.endAudio()
            stopTimeout = Task { [weak self] in
                do {
                    try await Task.sleep(for: .seconds(2))
                    guard self?.recordingID == id else { return }
                    self?.transcriptionIncomplete = true
                    self?.finishRecording(keepingFile: true)
                } catch {
                    return
                }
            }
        }
    }

    public func cancel() {
        startupID = nil
        finishRecording(keepingFile: false)
        discardLatestRecording()
    }

    func receive(
        result: SFSpeechRecognitionResult?,
        error: Error?,
        recordingID id: UUID,
        generation: Int
    ) {
        guard recordingID == id, generation == recognitionGeneration, !recognitionEnded else {
            return
        }
        if let result {
            recognitionRestarts = 0
            transcript = joinedTranscript(result.bestTranscription.formattedString)
            eventContinuation?.yield(.transcript(transcript))
            guard result.isFinal else { return }
            if stopContinuations.isEmpty {
                restartRecognition(recordingID: id)
            } else {
                endRecognitionAndFinish()
            }
            return
        }
        guard let error else { return }
        logRecognitionError(error)
        if stopContinuations.isEmpty {
            restartRecognition(recordingID: id)
        } else {
            transcriptionIncomplete = true
            endRecognitionAndFinish()
        }
    }

    func fail(_ error: Error, recordingID id: UUID) {
        guard recordingID == id else { return }
        transcriptionIncomplete = true
        finishRecording(keepingFile: true, interruption: error.localizedDescription)
    }

    func stopInput() {
        if audioEngine.isRunning { audioEngine.stop() }
        if hasInputTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInputTap = false
        }
    }

    func finishRecording(keepingFile: Bool, interruption: String? = nil) {
        let activeID = recordingID
        stopTimeout?.cancel()
        stopTimeout = nil
        stopInput()
        removeAudioInterruptionObserver()
        audioEngine.reset()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionInput?.stop()
        recognitionInput = nil
        recognitionRequest = nil
        recordingFile = nil
        recordingID = nil

        let result: SpeechRecording?
        if keepingFile, let recordingURL {
            let recoveredURL = interruption == nil
                ? recordingURL : preservePartialFile(recordingURL, recordingID: activeID)
            let completed = SpeechRecording(
                audioURL: recoveredURL, transcript: transcript,
                transcriptionIncomplete: transcriptionIncomplete,
                captureInterrupted: interruption != nil
            )
            result = completed
            latestRecording = completed
            latestRecordingIsRecovery = interruption != nil
            if let interruption {
                eventContinuation?.yield(.interrupted(completed, interruption))
            } else {
                eventContinuation?.yield(.finished(completed))
            }
        } else {
            if let activeID { VoiceRecordingJournal.remove(recordingID: activeID) }
            if let recordingURL { try? FileManager.default.removeItem(at: recordingURL) }
            result = nil
        }
        recordingURL = nil
        eventContinuation?.finish()
        eventContinuation = nil
        stopContinuations.forEach { $0.resume(returning: result) }
        stopContinuations.removeAll()
        releaseAudioSession()
    }
}

public enum SpeechRecordingError: LocalizedError {
    case alreadyRecording
    case microphoneUnavailable
    case recognizerUnavailable
    case interrupted

    public var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return "이미 음성을 녹음하고 있습니다."
        case .microphoneUnavailable:
            return "마이크를 사용할 수 없습니다."
        case .recognizerUnavailable:
            return "지금은 음성 인식을 사용할 수 없습니다."
        case .interrupted:
            return "전화나 다른 오디오 때문에 녹음이 중단됐어요."
        }
    }
}
