import AVFoundation
import Foundation
import OSLog
import Speech

nonisolated enum SpeechDebugLog {
    static func write(_ message: String) {
        let line = "\(Date()): \(message)\n"
        let url = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        )[0].appendingPathComponent("speech-debug.log")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

}

extension SpeechRecordingSession {
    func startAnalysisTasks(
        transcriber: DictationTranscriber,
        analyzer: SpeechAnalyzer,
        inputStream: AsyncStream<AnalyzerInput>,
        id: UUID
    ) {
        analyzeTask = Task {
            do {
                _ = try await analyzer.analyzeSequence(inputStream)
                SpeechDebugLog.write("analyzeSequence finished")
            } catch {
                let nsError = error as NSError
                SpeechDebugLog.write(
                    "analyzeSequence error: \(nsError.domain) code=\(nsError.code)"
                )
            }
        }
        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    self?.receive(result, recordingID: id)
                }
                SpeechDebugLog.write("results stream ended")
            } catch {
                let nsError = error as NSError
                SpeechDebugLog.write("results error: \(nsError.domain) code=\(nsError.code)")
                self?.logRecognitionError(error)
            }
            self?.recognitionDidFinish(recordingID: id)
        }
    }

    public func stop() async -> SpeechRecording? {
        guard let id = recordingID else { return latestRecording }

        return await withCheckedContinuation { continuation in
            let isFirstStop = stopContinuations.isEmpty
            stopContinuations.append(continuation)
            guard isFirstStop else { return }
            isStopping = true
            stopInput()
            analyzerInputContinuation?.finish()
            finalizeTask = Task { [weak self] in
                guard let self else { return }
                if let analyzeTask { await analyzeTask.value }
                try? await speechAnalyzer?.finalizeAndFinishThroughEndOfInput()
            }
            stopTimeout = Task { [weak self] in
                do {
                    try await Task.sleep(for: .seconds(10))
                    guard self?.recordingID == id else { return }
                    self?.transcriptionIncomplete = true
                    self?.finishRecording(keepingFile: true)
                } catch {
                    return
                }
            }
        }
    }

    func cancelAnalyzerWork() {
        finalizeTask?.cancel()
        finalizeTask = nil
        analyzeTask?.cancel()
        analyzeTask = nil
        resultsTask?.cancel()
        resultsTask = nil
        analyzerInputContinuation?.finish()
        analyzerInputContinuation = nil
        let analyzer = speechAnalyzer
        speechAnalyzer = nil
        if let analyzer {
            Task { await analyzer.cancelAndFinishNow() }
        }
    }

    func fail(_ error: Error, recordingID id: UUID) {
        guard recordingID == id else { return }
        let interruption = error as? SpeechRecordingError == .interrupted
            ? error.localizedDescription : nil
        if interruption == nil { transcriptionIncomplete = true }
        finishRecording(keepingFile: true, interruption: interruption)
    }

    func finishRecording(keepingFile: Bool, interruption: String? = nil) {
        let activeID = recordingID
        stopTimeout?.cancel()
        stopTimeout = nil
        cancelAnalyzerWork()
        isStopping = false
        transcriptAccumulator = SpeechTranscriptAccumulator()
        termMatcher = SpeechTermMatcher(replacements: [:])
        languageModelHint = nil
        removeObservers()
        stopInput()
        audioEngine.reset()
        recordingFile = nil
        recordingID = nil

        let result: SpeechRecording?
        if keepingFile, let recordingURL, let activeID {
            let recoveredURL = recordingURL
            let completed = SpeechRecording(
                recordingID: activeID, audioURL: recoveredURL, transcript: transcript,
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
        } else if !keepingFile {
            if let activeID {
                VoiceRecordingJournal.remove(recordingID: activeID)
            } else if let recordingURL {
                VoiceRecordingJournal.remove(filePath: recordingURL.path)
            }
            if let recordingURL { try? FileManager.default.removeItem(at: recordingURL) }
            result = nil
        } else {
            result = nil
            eventContinuation?.yield(.failed("녹음 식별자를 확인하지 못했어요. 원본은 보관됩니다."))
        }
        recordingURL = nil
        eventContinuation?.finish()
        eventContinuation = nil
        stopContinuations.forEach { $0.resume(returning: result) }
        stopContinuations.removeAll()
        releaseAudioSession()
    }

    func discardLatestRecording() {
        if let latestRecording {
            VoiceRecordingJournal.remove(filePath: latestRecording.audioURL.path)
            try? FileManager.default.removeItem(at: latestRecording.audioURL)
        }
        latestRecording = nil
        latestRecordingIsRecovery = false
    }

    func receive(_ result: DictationTranscriber.Result, recordingID id: UUID) {
        guard recordingID == id else { return }
        guard let text = transcriptAccumulator.accept(
            result, termMatcher: &termMatcher, unitNormalizer: unitNormalizer
        ) else { return }
        transcript = text
        eventContinuation?.yield(.transcript(transcript))
    }

    func recognitionDidFinish(recordingID id: UUID) {
        guard recordingID == id else { return }
        if stopContinuations.isEmpty {
            transcriptionIncomplete = true
            eventContinuation?.yield(.transcriptionUnavailable)
        }
        finishRecording(keepingFile: true)
    }

    func observeSystemEvents(recordingID id: UUID) {
        observe(AVAudioSession.didBecomeInactiveNotification) { [weak self] _ in
            guard let self, self.recordingID != nil, !self.isStopping else { return }
            self.fail(SpeechRecordingError.interrupted, recordingID: id)
        }
        observe(.AVAudioEngineConfigurationChange, object: audioEngine) { [weak self] _ in
            guard let self, self.recordingID != nil, !self.isStopping else { return }
            self.finishRecording(keepingFile: true)
        }
        observe(AVAudioSession.mediaServicesWereResetNotification) { [weak self] _ in
            guard let self, self.recordingID != nil else { return }
            self.finishRecording(keepingFile: true)
        }
    }

    func observe(
        _ name: Notification.Name,
        object: Any? = nil,
        handler: @escaping @MainActor (Notification) -> Void
    ) {
        observers.append(NotificationCenter.default.addObserver(
            forName: name,
            object: object,
            queue: .main
        ) { note in
            Task { @MainActor in handler(note) }
        })
    }

    func removeObservers() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }

    func logRecognitionError(_ error: Error) {
        let underlying = error as NSError
        let domain = underlying.domain
        let code = underlying.code
        Logger(subsystem: "Labcord", category: "PhoneSpeech")
            .error("Speech recognition error: \(domain, privacy: .public) code=\(code)")
    }
}
