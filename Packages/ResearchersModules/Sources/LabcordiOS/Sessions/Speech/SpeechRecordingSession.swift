import AVFoundation
import Foundation
import OSLog
import Speech

private final class SpeechRecognitionInput: @unchecked Sendable {
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
}

@MainActor
public final class SpeechRecordingSession {
    private let audioEngine = AVAudioEngine()
    private let audioSessionQueue = DispatchQueue(label: "com.researchers.speech.audio-session")
    private let locale: Locale

    private var startupID: UUID?
    private var recordingID: UUID?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionInput: SpeechRecognitionInput?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var eventContinuation: AsyncStream<SpeechRecordingEvent>.Continuation?
    private var stopContinuations: [CheckedContinuation<SpeechRecording?, Never>] = []
    private var stopTimeout: Task<Void, Never>?
    private var recordingURL: URL?
    private var recordingFile: AVAudioFile?
    private var latestRecording: SpeechRecording?
    private var latestRecordingIsRecovery = false
    private var hasInputTap = false
    private var audioActivationPending = false
    private var ownsAudioSession = false
    private var transcript = ""
    private var recognitionEnded = false
    private var transcriptionIncomplete = false

    public init(locale: Locale = Locale(identifier: "ko-KR")) {
        self.locale = locale
    }

    public func start(
        contextualStrings: [String] = []
    ) async throws -> AsyncStream<SpeechRecordingEvent> {
        guard startupID == nil, recordingID == nil else {
            throw SpeechRecordingError.alreadyRecording
        }
        discardLatestRecording()

        let id = UUID()
        startupID = id
        defer { if startupID == id { startupID = nil } }

        let recognizer = try authorizedRecognizer()
        try await activateForStartup(id)

        do {
            return try beginRecording(
                id: id, recognizer: recognizer, contextualStrings: contextualStrings
            )
        } catch {
            finishRecording(keepingFile: false)
            discardLatestRecording()
            throw error
        }
    }

    private func authorizedRecognizer() throws -> SFSpeechRecognizer {
        guard AVAudioApplication.shared.recordPermission == .granted else {
            throw PermissionAccessError(.microphone)
        }
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw PermissionAccessError(.speechRecognition)
        }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw SpeechRecordingError.recognizerUnavailable
        }
        return recognizer
    }

    private func activateForStartup(_ id: UUID) async throws {
        audioActivationPending = true
        do {
            try await activateAudioSession()
        } catch {
            if startupID == id { releaseAudioSession() }
            throw error
        }
        guard startupID == id, !Task.isCancelled else {
            if startupID == id { releaseAudioSession() }
            throw CancellationError()
        }
        audioActivationPending = false
        ownsAudioSession = true
    }

    private func beginRecording(
        id: UUID,
        recognizer: SFSpeechRecognizer,
        contextualStrings: [String]
    ) throws -> AsyncStream<SpeechRecordingEvent> {
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { throw SpeechRecordingError.microphoneUnavailable }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("speech-\(id.uuidString).caf")
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        recordingURL = url
        recordingFile = file

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.contextualStrings = contextualStrings
        recognitionRequest = request
        let input = SpeechRecognitionInput(request)
        recognitionInput = input
        recordingID = id
        transcript = ""
        recognitionEnded = false
        transcriptionIncomplete = false

        let (stream, continuation) = AsyncStream<SpeechRecordingEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        eventContinuation = continuation

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                self?.receive(result: result, error: error, recordingID: id)
            }
        }

        installInputTap(on: inputNode, format: format, input: input, file: file, id: id)
        audioEngine.prepare()
        try audioEngine.start()
        try Task.checkCancellation()
        guard recordingID == id else { throw SpeechRecordingError.recognizerUnavailable }
        return stream
    }

    private func installInputTap(
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

    private func receive(
        result: SFSpeechRecognitionResult?,
        error: Error?,
        recordingID id: UUID
    ) {
        guard recordingID == id, !recognitionEnded else { return }
        if let result {
            transcript = result.bestTranscription.formattedString
            eventContinuation?.yield(.transcript(transcript))
            if result.isFinal {
                recognitionEnded = true
                recognitionInput?.stop()
                if !stopContinuations.isEmpty {
                    finishRecording(keepingFile: true)
                } else {
                    logRecognitionEndedEarly()
                    transcriptionIncomplete = true
                    eventContinuation?.yield(.transcriptionUnavailable)
                }
                return
            }
        }
        if let error {
            logRecognitionError(error)
            recognitionEnded = true
            recognitionInput?.stop()
            transcriptionIncomplete = true
            eventContinuation?.yield(.transcriptionUnavailable)
            if !stopContinuations.isEmpty { finishRecording(keepingFile: true) }
        }
    }

    private func fail(_ error: Error, recordingID id: UUID) {
        guard recordingID == id else { return }
        transcriptionIncomplete = true
        finishRecording(keepingFile: true, interruption: error.localizedDescription)
    }

    private func stopInput() {
        if audioEngine.isRunning { audioEngine.stop() }
        if hasInputTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInputTap = false
        }
    }

    private func finishRecording(keepingFile: Bool, interruption: String? = nil) {
        stopTimeout?.cancel()
        stopTimeout = nil
        stopInput()
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
                ? recordingURL : preservePartialFile(recordingURL)
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

    private func discardLatestRecording() {
        if let latestRecording, !latestRecordingIsRecovery {
            try? FileManager.default.removeItem(at: latestRecording.audioURL)
        }
        latestRecording = nil
        latestRecordingIsRecovery = false
    }

}

private extension SpeechRecordingSession {
    func logRecognitionEndedEarly() {
        Logger(subsystem: "Labcord", category: "PhoneSpeech")
            .warning("Speech recognition ended before recording stopped")
    }

    func logRecognitionError(_ error: Error) {
        let underlying = error as NSError
        let domain = underlying.domain
        let code = underlying.code
        Logger(subsystem: "Labcord", category: "PhoneSpeech")
            .error("Speech recognition error: \(domain, privacy: .public) code=\(code)")
    }

    func preservePartialFile(_ original: URL) -> URL {
        let directory = URL.applicationSupportDirectory
            .appending(path: "IncompleteVoiceRecordings")
        let destination = directory.appending(path: original.lastPathComponent)
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true
            )
            try FileManager.default.moveItem(at: original, to: destination)
            return destination
        } catch {
            return original
        }
    }

    func activateAudioSession() async throws {
        try await withCheckedThrowingContinuation { continuation in
            audioSessionQueue.async {
                do {
                    let audioSession = AVAudioSession.sharedInstance()
                    try audioSession.setCategory(.record, mode: .measurement)
                    try audioSession.setActive(true)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func releaseAudioSession() {
        guard audioActivationPending || ownsAudioSession else { return }
        audioActivationPending = false
        ownsAudioSession = false
        audioSessionQueue.async {
            try? AVAudioSession.sharedInstance().setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
        }
    }
}

public enum SpeechRecordingError: LocalizedError {
    case alreadyRecording
    case microphoneUnavailable
    case recognizerUnavailable

    public var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return "이미 음성을 녹음하고 있습니다."
        case .microphoneUnavailable:
            return "마이크를 사용할 수 없습니다."
        case .recognizerUnavailable:
            return "지금은 음성 인식을 사용할 수 없습니다."
        }
    }
}
