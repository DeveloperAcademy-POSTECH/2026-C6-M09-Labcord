import AVFoundation
import Foundation
import Speech

@MainActor
public final class SpeechRecordingSession {
    let audioEngine = AVAudioEngine()
    let audioSessionQueue = DispatchQueue(label: "com.researchers.speech.audio-session")
    let analyzerInputQueue = DispatchQueue(label: "com.researchers.speech.analyzer-input")
    let locale: Locale

    var startupID: UUID?
    var recordingID: UUID?
    var speechAnalyzer: SpeechAnalyzer?
    var analyzerInputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    var analyzeTask: Task<Void, Never>?
    var resultsTask: Task<Void, Never>?
    var finalizeTask: Task<Void, Never>?
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
    var isStopping = false
    var transcriptAccumulator = SpeechTranscriptAccumulator()
    var transcript = ""
    var termMatcher = SpeechTermMatcher(replacements: [:])
    var unitNormalizer = SpeechUnitNormalizer(units: [])
    var languageModelHint: SpeechLanguageModelHint?
    var observers: [NSObjectProtocol] = []
    var experimentID: UUID?
    var transcriptionIncomplete = false

    public init(locale: Locale = Locale(identifier: "ko-KR")) {
        self.locale = locale
    }

    public func start(
        experimentID: UUID, contextualStrings: [String] = [],
        phoneticReplacements: [String: String] = [:], units: [String] = [],
        languageModelHint: SpeechLanguageModelHint? = nil
    ) async throws -> AsyncStream<SpeechRecordingEvent> {
        guard startupID == nil, recordingID == nil else {
            throw SpeechRecordingError.alreadyRecording
        }

        latestRecording = nil
        latestRecordingIsRecovery = false
        self.experimentID = experimentID
        self.termMatcher = SpeechTermMatcher(replacements: phoneticReplacements)
        self.unitNormalizer = SpeechUnitNormalizer(units: units)
        self.languageModelHint = languageModelHint
        SpeechDebugLog.write("phonetic replacements: \(phoneticReplacements.count)")
        try checkPermissions()
        let transcriber = try await Self.makeTranscriber(
            locale: locale, languageModelHint: languageModelHint
        )

        let id = UUID()
        startupID = id
        defer { if startupID == id { startupID = nil } }

        try await activateForStartup(id)

        do {
            return try await beginRecording(
                id: id, transcriber: transcriber,
                contextualStrings: Array((unitNormalizer.hints + contextualStrings).prefix(100))
            )
        } catch {
            finishRecording(keepingFile: false)
            discardLatestRecording()
            throw error
        }
    }

    private func checkPermissions() throws {
        guard AVAudioApplication.shared.recordPermission == .granted else {
            throw PermissionAccessError(.microphone)
        }
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw PermissionAccessError(.speechRecognition)
        }
    }

    static func makeTranscriber(
        locale: Locale, languageModelHint: SpeechLanguageModelHint?
    ) async throws -> DictationTranscriber {
        var resolvedLocale: Locale?
        for candidate in [locale, .autoupdatingCurrent] {
            if let supported = await DictationTranscriber.supportedLocale(
                equivalentTo: candidate
            ) {
                resolvedLocale = supported
                break
            }
        }
        guard let resolvedLocale else {
            throw SpeechRecordingError.recognizerUnavailable
        }
        let preset = DictationTranscriber.Preset.progressiveLongDictation
        var contentHints = preset.contentHints
        if let languageModelHint {
            contentHints.insert(.customizedLanguage(
                modelConfiguration: languageModelHint.makeConfiguration()
            ))
        }

        var reportingOptions = preset.reportingOptions
        reportingOptions.insert(.alternativeTranscriptions)
        let transcriber = DictationTranscriber(
            locale: resolvedLocale,
            contentHints: contentHints,
            transcriptionOptions: preset.transcriptionOptions,
            reportingOptions: reportingOptions,
            attributeOptions: preset.attributeOptions
        )
        let status = await AssetInventory.status(forModules: [transcriber])
        SpeechDebugLog.write("asset status: \(status)")
        guard status != .installed else { return transcriber }
        guard let request = try await AssetInventory.assetInstallationRequest(
            supporting: [transcriber]
        ) else {
            throw SpeechRecordingError.recognizerUnavailable
        }
        try await request.downloadAndInstall()
        SpeechDebugLog.write("asset installed")
        return transcriber
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

    // swiftlint:disable:next function_body_length
    private func beginRecording(
        id: UUID,
        transcriber: DictationTranscriber,
        contextualStrings: [String]
    ) async throws -> AsyncStream<SpeechRecordingEvent> {
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { throw SpeechRecordingError.microphoneUnavailable }

        let directory = URL.applicationSupportDirectory
            .appending(path: "IncompleteVoiceRecordings/\(experimentID?.uuidString ?? "unknown")")
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        let url = directory.appendingPathComponent("speech-\(id.uuidString).caf")
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        recordingURL = url
        recordingFile = file

        if let experimentID {
            try VoiceRecordingJournal.beginOwnedRecording(VoiceRecordingJournal.Entry(
                experimentID: experimentID, recordingID: id,
                filePath: url.path, startedAt: Date()
            ))
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        SpeechDebugLog.write("contextualStrings: \(contextualStrings.count)")
        if !contextualStrings.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = contextualStrings
            try await analyzer.setContext(context)
        }
        let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber]
        ) ?? format
        try await analyzer.prepareToAnalyze(in: analyzerFormat)
        let converter = try await makeInputConverter(
            for: transcriber, inputFormat: format, analyzerFormat: analyzerFormat
        )

        let (inputStream, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream()
        analyzerInputContinuation = inputContinuation

        transcriptAccumulator = SpeechTranscriptAccumulator()
        transcript = ""
        transcriptionIncomplete = false
        isStopping = false
        speechAnalyzer = analyzer
        recordingID = id

        let (stream, continuation) = AsyncStream<SpeechRecordingEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        eventContinuation = continuation

        startAnalysisTasks(
            transcriber: transcriber, analyzer: analyzer,
            inputStream: inputStream, id: id
        )

        observeSystemEvents(recordingID: id)
        try installInputTap(on: inputNode, format: format, file: file, converter: converter)
        audioEngine.prepare()
        try audioEngine.start()
        try Task.checkCancellation()
        guard recordingID == id else { throw SpeechRecordingError.recognizerUnavailable }
        return stream
    }

    private func makeInputConverter(
        for transcriber: DictationTranscriber,
        inputFormat: AVAudioFormat,
        analyzerFormat: AVAudioFormat
    ) async throws -> AnalyzerInputConverter? {
        let isCompatible = inputFormat.sampleRate == analyzerFormat.sampleRate
            && inputFormat.channelCount == analyzerFormat.channelCount
            && inputFormat.commonFormat == analyzerFormat.commonFormat
            && inputFormat.isInterleaved == analyzerFormat.isInterleaved
        guard !isCompatible else { return nil }
        return try await AnalyzerInputConverter.converter(compatibleWith: [transcriber])
    }

    private func installInputTap(
        on inputNode: AVAudioInputNode,
        format: AVAudioFormat,
        file: AVAudioFile,
        converter: AnalyzerInputConverter?
    ) throws {
        guard let id = recordingID,
              let continuation = analyzerInputContinuation else {
            throw SpeechRecordingError.microphoneUnavailable
        }
        let converterBox = ConverterBox(converter)
        let queue = analyzerInputQueue
        try inputNode.installAudioTap(
            onBus: 0, bufferSize: 1024, format: format
        ) { [weak self] buffer, _ in
            do {
                try file.write(from: buffer)
            } catch {
                Task { @MainActor in
                    self?.fail(error, recordingID: id)
                }
            }
            queue.async {
                let pcmBuffer = AVAudioPCMBuffer(copying: buffer)
                do {
                    if let converter = converterBox.converter {
                        for input in try converter.convert(pcmBuffer, at: nil) {
                            continuation.yield(input)
                        }
                    } else {
                        continuation.yield(AnalyzerInput(buffer: pcmBuffer))
                    }
                } catch {
                    let nsError = error as NSError
                    SpeechDebugLog.write("convert error: \(nsError.domain) code=\(nsError.code)")
                }
            }
        }
        hasInputTap = true
    }

}

extension SpeechRecordingSession {
    public func cancel() {
        startupID = nil
        finishRecording(keepingFile: false)
        discardLatestRecording()
    }

    func stopInput() {
        if audioEngine.isRunning { audioEngine.stop() }
        if hasInputTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInputTap = false
        }
    }

    func activateAudioSession() async throws {
        try await withCheckedThrowingContinuation { continuation in
            audioSessionQueue.async {
                do {
                    let audioSession = AVAudioSession.sharedInstance()
                    try audioSession.setCategory(.playAndRecord, mode: .spokenAudio)
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

private final class ConverterBox: @unchecked Sendable {
    let converter: AnalyzerInputConverter?

    init(_ converter: AnalyzerInputConverter?) {
        self.converter = converter
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
