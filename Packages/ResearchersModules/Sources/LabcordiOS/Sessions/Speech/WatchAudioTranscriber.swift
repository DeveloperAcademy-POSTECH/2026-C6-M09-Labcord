import AVFoundation
import Foundation
import LabcordShared
import Speech

@MainActor
final class WatchAudioTranscriber {
    let header: WatchAudioHeader
    private let analyzer: SpeechAnalyzer
    private let input: AsyncStream<AnalyzerInput>.Continuation
    private let converter: AnalyzerInputConverter?
    private var analyzeTask: Task<Void, Error>?
    private var resultsTask: Task<Void, Error>?
    private var finalizeTask: Task<Void, Never>?
    private var timeout: Task<Void, Never>?
    private var waiter: CheckedContinuation<String, Error>?
    private var terminal: Result<String, Error>?
    private var transcriptAccumulator = SpeechTranscriptAccumulator()
    private var transcript = ""
    private var revision: UInt64 = 0
    private var throughSample: Int64 = 0
    private let generationID = UUID()
    private let emit: (WatchAudioTranscript) -> Void
    private var termMatcher: SpeechTermMatcher
    private let unitNormalizer: SpeechUnitNormalizer

    init(
        header: WatchAudioHeader, locale: Locale, contextualStrings: [String],
        replacements: [String: String], units: [String],
        languageModelHint: SpeechLanguageModelHint?,
        emit: @escaping (WatchAudioTranscript) -> Void
    ) async throws {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw WatchAudioError.permissionDenied
        }
        let transcriber = try await SpeechRecordingSession.makeTranscriber(
            locale: locale, languageModelHint: languageModelHint
        )
        try Task.checkCancellation()
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let normalizer = SpeechUnitNormalizer(units: units)
        let hints = Array((normalizer.hints + contextualStrings).prefix(100))
        if !hints.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = hints
            try await analyzer.setContext(context)
        }
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16, sampleRate: Double(header.sampleRate),
            channels: 1, interleaved: false
        ) else { throw WatchAudioError.invalidAudio }
        let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber]
        ) ?? format
        try await analyzer.prepareToAnalyze(in: analyzerFormat)
        let compatible = format.sampleRate == analyzerFormat.sampleRate
            && format.channelCount == analyzerFormat.channelCount
            && format.commonFormat == analyzerFormat.commonFormat
            && format.isInterleaved == analyzerFormat.isInterleaved
        let converter = compatible ? nil : try await AnalyzerInputConverter.converter(
            compatibleWith: [transcriber]
        )
        try Task.checkCancellation()
        let (stream, input) = AsyncStream<AnalyzerInput>.makeStream()
        self.header = header
        self.analyzer = analyzer
        self.input = input
        self.converter = converter
        self.emit = emit
        self.termMatcher = SpeechTermMatcher(replacements: replacements)
        self.unitNormalizer = normalizer
        analyzeTask = Task { _ = try await analyzer.analyzeSequence(stream) }
        resultsTask = Task { [weak self] in
            for try await result in transcriber.results {
                self?.receive(result)
            }
        }
    }

    func append(_ chunk: WatchAudioChunk) throws {
        if case let .failure(error) = terminal { throw error }
        guard chunk.header == header, chunk.firstSample == throughSample, terminal == nil,
              let format = AVAudioFormat(
                commonFormat: .pcmFormatInt16, sampleRate: Double(header.sampleRate),
                channels: 1, interleaved: false
              ), let buffer = AVAudioPCMBuffer(
                pcmFormat: format, frameCapacity: AVAudioFrameCount(chunk.sampleCount)
              ), let samples = buffer.int16ChannelData?[0] else {
            throw WatchAudioError.invalidAudio
        }
        buffer.frameLength = AVAudioFrameCount(chunk.sampleCount)
        chunk.pcm.copyBytes(to: UnsafeMutableRawBufferPointer(
            start: samples, count: chunk.pcm.count
        ))
        if let converter {
            for item in try converter.convert(buffer, at: nil) { input.yield(item) }
        } else {
            input.yield(AnalyzerInput(buffer: buffer))
        }
        throughSample += chunk.sampleCount
    }

    func finish() async throws -> String {
        if let terminal { return try terminal.get() }
        input.finish()
        return try await withCheckedThrowingContinuation { continuation in
            waiter = continuation
            finalizeTask = Task { [weak self] in
                guard let self else { return }
                do {
                    try await analyzeTask?.value
                    try await analyzer.finalizeAndFinishThroughEndOfInput()
                    try await resultsTask?.value
                    guard !Task.isCancelled else { return }
                    publish(isFinal: true)
                    complete(.success(transcript))
                } catch { complete(.failure(error)) }
            }
            timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                self?.complete(.failure(WatchAudioError.recognitionUnavailable))
                self?.stopTasks()
            }
        }
    }

    func cancel() {
        complete(.failure(CancellationError()))
        stopTasks()
    }

    private func stopTasks() {
        input.finish()
        finalizeTask?.cancel()
        analyzeTask?.cancel()
        resultsTask?.cancel()
        Task { await analyzer.cancelAndFinishNow() }
    }

    private func receive(_ result: DictationTranscriber.Result) {
        guard terminal == nil else { return }
        guard let text = transcriptAccumulator.accept(
            result, termMatcher: &termMatcher, unitNormalizer: unitNormalizer
        ) else { return }
        transcript = text
        publish(isFinal: false)
    }

    private func publish(isFinal: Bool) {
        revision += 1
        emit(WatchAudioTranscript(
            header: header, throughSample: throughSample, revision: revision,
            generationID: generationID, text: transcript, isFinal: isFinal
        ))
    }

    private func complete(_ result: Result<String, Error>) {
        guard terminal == nil else { return }
        terminal = result
        timeout?.cancel()
        timeout = nil
        waiter?.resume(with: result)
        waiter = nil
    }
}
