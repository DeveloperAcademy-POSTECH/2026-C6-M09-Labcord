import AVFoundation
import Foundation
import OSLog
import Speech

extension SpeechRecordingSession {
    func authorizedRecognizer() throws -> SFSpeechRecognizer {
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

    func activateForStartup(_ id: UUID) async throws {
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

    func makeRecognitionRequest() -> SFSpeechAudioBufferRecognitionRequest {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.contextualStrings = contextualStrings
        if recognizer?.supportsOnDeviceRecognition == true {
            request.requiresOnDeviceRecognition = true
        }
        return request
    }

    func startRecognitionTask(
        id: UUID, recognizer: SFSpeechRecognizer, request: SFSpeechAudioBufferRecognitionRequest
    ) {
        recognitionGeneration += 1
        let generation = recognitionGeneration
        recognitionRequest = request
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                self?.receive(
                    result: result, error: error, recordingID: id, generation: generation
                )
            }
        }
    }

    func restartRecognition(recordingID id: UUID) {
        // 서버 인식은 약 1분 뒤 끝나므로 녹음 파일은 유지하고 인식만 다시 시작한다.
        recognitionRestarts += 1
        guard recognitionRestarts <= 8, let recognizer else {
            transcriptionIncomplete = true
            eventContinuation?.yield(.transcriptionUnavailable)
            return
        }
        committedTranscript = transcript
        recognitionTask?.cancel()
        recognitionTask = nil
        let request = makeRecognitionRequest()
        recognitionInput?.replace(request)
        startRecognitionTask(id: id, recognizer: recognizer, request: request)
    }

    func endRecognitionAndFinish() {
        recognitionEnded = true
        recognitionInput?.stop()
        finishRecording(keepingFile: true)
    }

    func joinedTranscript(_ segment: String) -> String {
        guard !committedTranscript.isEmpty else { return segment }
        guard !segment.isEmpty else { return committedTranscript }
        if segment.hasPrefix(committedTranscript) { return segment }
        return committedTranscript + " " + segment
    }

    func observeAudioInterruptions(recordingID id: UUID) {
        removeAudioInterruptionObserver()
        audioInterruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: nil
        ) { [weak self] notification in
            let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard rawType == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { @MainActor in
                self?.fail(SpeechRecordingError.interrupted, recordingID: id)
            }
        }
    }

    func removeAudioInterruptionObserver() {
        if let audioInterruptionObserver {
            NotificationCenter.default.removeObserver(audioInterruptionObserver)
        }
        audioInterruptionObserver = nil
    }

    func discardLatestRecording() {
        if let latestRecording {
            VoiceRecordingJournal.remove(filePath: latestRecording.audioURL.path)
            try? FileManager.default.removeItem(at: latestRecording.audioURL)
        }
        latestRecording = nil
        latestRecordingIsRecovery = false
    }

    func logRecognitionError(_ error: Error) {
        let underlying = error as NSError
        let domain = underlying.domain
        let code = underlying.code
        Logger(subsystem: "Labcord", category: "PhoneSpeech")
            .error("Speech recognition error: \(domain, privacy: .public) code=\(code)")
    }

    func preservePartialFile(_ original: URL, recordingID: UUID?) -> URL {
        let folder = experimentID.map { "IncompleteVoiceRecordings/\($0.uuidString)" }
            ?? "IncompleteVoiceRecordings"
        let directory = URL.applicationSupportDirectory.appending(path: folder)
        let destination = directory.appending(path: original.lastPathComponent)
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true
            )
            try FileManager.default.moveItem(at: original, to: destination)
            if let recordingID {
                VoiceRecordingJournal.relocate(recordingID: recordingID, to: destination)
            }
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
