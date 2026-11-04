import AVFoundation
import Foundation
import LabcordShared
import Speech

/// External audio only: this class never activates or taps the iPhone microphone.
@MainActor
final class WatchAudioTranscriber {
    let header: WatchAudioHeader
    private let request = SFSpeechAudioBufferRecognitionRequest()
    private var task: SFSpeechRecognitionTask?
    private var finalWaiter: CheckedContinuation<String, Error>?
    private var terminal: Result<String, Error>?
    private var timeout: Task<Void, Never>?
    private var revision: UInt64 = 0
    private var throughSample: Int64 = 0
    private let generationID = UUID()
    private let emit: (WatchAudioTranscript) -> Void

    init(
        header: WatchAudioHeader, locale: Locale, contextualStrings: [String],
        emit: @escaping (WatchAudioTranscript) -> Void
    ) throws {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw WatchAudioError.permissionDenied
        }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw WatchAudioError.recognitionUnavailable
        }
        self.header = header
        self.emit = emit
        request.shouldReportPartialResults = true
        request.contextualStrings = contextualStrings
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result { self.receive(result) }
                if let error { self.complete(.failure(error)) }
            }
        }
    }

    func append(_ chunk: WatchAudioChunk) throws {
        guard chunk.header == header, chunk.firstSample == throughSample, terminal == nil,
              let format = AVAudioFormat(
                commonFormat: .pcmFormatInt16, sampleRate: Double(header.sampleRate),
                channels: 1, interleaved: false
              ),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format, frameCapacity: AVAudioFrameCount(chunk.sampleCount)
              ), let samples = buffer.int16ChannelData?[0] else {
            throw WatchAudioError.invalidAudio
        }
        buffer.frameLength = AVAudioFrameCount(chunk.sampleCount)
        chunk.pcm.copyBytes(to: UnsafeMutableRawBufferPointer(
            start: samples, count: chunk.pcm.count
        ))
        request.append(buffer)
        throughSample += chunk.sampleCount
    }

    func finish() async throws -> String {
        request.endAudio()
        if let terminal { return try terminal.get() }
        return try await withCheckedThrowingContinuation { continuation in
            finalWaiter = continuation
            timeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                self?.complete(.failure(WatchAudioError.recognitionUnavailable))
                self?.task?.cancel()
            }
        }
    }

    func cancel() {
        complete(.failure(CancellationError()))
        task?.cancel()
    }

    private func receive(_ result: SFSpeechRecognitionResult) {
        guard terminal == nil else { return }
        revision += 1
        let text = result.bestTranscription.formattedString
        emit(WatchAudioTranscript(
            header: header, throughSample: throughSample, revision: revision,
            generationID: generationID,
            text: text, isFinal: result.isFinal
        ))
        if result.isFinal { complete(.success(text)) }
    }

    private func complete(_ result: Result<String, Error>) {
        guard terminal == nil else { return }
        terminal = result
        timeout?.cancel()
        timeout = nil
        finalWaiter?.resume(with: result)
        finalWaiter = nil
    }
}
