import ComposableArchitecture
import Foundation
import LabcordShared
import LabcordWatchOS

@Reducer
struct VoiceRecordFeature {
    enum Phase: Equatable {
        case starting, recording, awaitingTransfer, transcribing, transcript, saving, saved, failed
    }

    @ObservableState
    struct State: Equatable {
        let experimentID: UUID
        var phase: Phase = .starting
        var header: WatchAudioHeader?
        var isVoiceDetected = false
        var isVoiceReleasePending = false
        var transcript = ""
        var errorMessage: String?
        var hasRetainedAudio = false
        var autoSaveSeconds = 3
        var isClosing = false
        var shouldDismiss = false
    }

    enum Action {
        case appeared, disappeared, finishTapped, retryTapped, rerecordTapped
        case saveTapped, cancelTapped, cancelQueued, autoSaveTick(UUID)
        case started(WatchAudioHeader)
        case captureEvent(WatchAudioCaptureEvent)
        case voiceSilenceElapsed
        case receipt(WatchAudioReceipt)
        case stopped(WatchAudioHeader)
        case failed(String)
    }

    private nonisolated enum CancelID: Hashable, Sendable {
        case capture, receipts, voiceRelease, autoSave
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .appeared:
                guard !state.isClosing else { return .none }
                let experimentID = state.experimentID
                return .merge(
                    .run { send in
                        do {
                            let stream = try await WatchVoiceRecordingService.shared.start(
                                experimentID: experimentID
                            )
                            let header = await WatchVoiceRecordingService.shared.activeRecording
                            if let header {
                                await send(.started(header))
                            }
                            for await event in stream { await send(.captureEvent(event)) }
                        } catch {
                            await send(.failed(Self.message(for: error)))
                        }
                    }
                    .cancellable(id: CancelID.capture, cancelInFlight: true),
                    .run { send in
                        for await receipt in await WatchVoiceRecordingService.shared.receipts() {
                            await send(.receipt(receipt))
                        }
                    }
                    .cancellable(id: CancelID.receipts, cancelInFlight: true)
                )

            case let .started(header):
                guard !state.isClosing, state.phase == .starting else { return .none }
                state.header = header
                state.phase = .recording
                return .none

            case let .captureEvent(event):
                guard !state.isClosing else { return .none }
                switch event {
                case let .recording(header):
                    if state.phase == .starting {
                        state.header = header
                        state.phase = .recording
                    }
                case let .levels(levels):
                    guard state.phase == .recording else { return .none }
                    if levels.contains(where: { $0 > 0.05 }) {
                        state.isVoiceDetected = true
                        state.isVoiceReleasePending = false
                        return .cancel(id: CancelID.voiceRelease)
                    }
                    guard state.isVoiceDetected, !state.isVoiceReleasePending else { return .none }
                    state.isVoiceReleasePending = true
                    return .run { send in
                        try await Task.sleep(for: .milliseconds(350))
                        await send(.voiceSilenceElapsed)
                    }
                    .cancellable(id: CancelID.voiceRelease)
                case .retaining, .retained:
                    break
                case let .failed(error):
                    state.phase = .failed
                    state.errorMessage = Self.message(for: error)
                    state.isVoiceDetected = false
                    state.isVoiceReleasePending = false
                    return .merge(
                        .cancel(id: CancelID.voiceRelease),
                        .run { _ in
                            await WatchVoiceRecordingService.shared.stopAndQueueIfNeeded()
                        }
                    )
                }
                return .none

            case .voiceSilenceElapsed:
                guard state.phase == .recording, state.isVoiceReleasePending else { return .none }
                state.isVoiceDetected = false
                state.isVoiceReleasePending = false
                return .none

            case .finishTapped:
                guard state.phase == .recording, !state.isClosing else { return .none }
                state.phase = .awaitingTransfer
                state.isVoiceDetected = false
                state.isVoiceReleasePending = false
                return .merge(
                    .cancel(id: CancelID.voiceRelease),
                    .run { send in
                        do {
                            let header = try await WatchVoiceRecordingService.shared.stopAndQueue()
                            await send(.stopped(header))
                        } catch {
                            await send(.failed(Self.message(for: error)))
                        }
                    }
                )

            case let .stopped(header):
                guard !state.isClosing, state.header == header else { return .none }
                state.hasRetainedAudio = true
                return .none

            case let .receipt(receipt):
                return handleReceipt(state: &state, receipt: receipt)

            case let .autoSaveTick(recordingID):
                guard !state.isClosing, state.phase == .transcript,
                      state.header?.recordingID == recordingID else { return .none }
                state.autoSaveSeconds -= 1
                if state.autoSaveSeconds == 0 { return .send(.saveTapped) }
                return .none

            case .saveTapped:
                guard !state.isClosing, state.phase == .transcript,
                      let header = state.header else { return .none }
                state.phase = .saving
                return .merge(
                    .cancel(id: CancelID.autoSave),
                    .run { _ in await WatchVoiceRecordingService.shared.confirm(header) }
                )

            case .rerecordTapped:
                guard state.phase == .transcript, let header = state.header else { return .none }
                state.phase = .starting
                state.header = nil
                state.transcript = ""
                state.hasRetainedAudio = false
                state.autoSaveSeconds = 3
                state.isVoiceDetected = false
                state.isVoiceReleasePending = false
                let experimentID = state.experimentID
                return .merge(
                    .cancel(id: CancelID.autoSave),
                    .cancel(id: CancelID.capture),
                    .run { send in
                        await WatchVoiceRecordingService.shared.cancel(header)
                        guard !Task.isCancelled else { return }
                        let stream = try? await WatchVoiceRecordingService.shared.start(
                            experimentID: experimentID
                        )
                        guard let stream else {
                            await send(.failed("녹음을 다시 시작할 수 없어요."))
                            return
                        }
                        if let active = await WatchVoiceRecordingService.shared.activeRecording {
                            await send(.started(active))
                        }
                        for await event in stream { await send(.captureEvent(event)) }
                    }
                    .cancellable(id: CancelID.capture, cancelInFlight: true)
                )

            case .cancelTapped:
                guard state.phase != .saved, !state.isClosing else { return .none }
                state.isClosing = true
                let header = state.header
                return .merge(
                    .cancel(id: CancelID.capture),
                    .cancel(id: CancelID.receipts),
                    .cancel(id: CancelID.voiceRelease),
                    .cancel(id: CancelID.autoSave),
                    .run { send in
                        await WatchVoiceRecordingService.shared.cancelInBackground(header)
                        await send(.cancelQueued)
                    }
                )

            case .cancelQueued:
                guard state.isClosing else { return .none }
                state.shouldDismiss = true
                return .none

            case .retryTapped:
                guard state.phase == .failed else { return .none }
                if state.hasRetainedAudio {
                    state.phase = .awaitingTransfer
                    state.errorMessage = nil
                    let header = state.header
                    return .run { send in
                        if let receipt = await WatchVoiceRecordingService.shared.retryDelivery(
                            for: header
                        ) {
                            await send(.receipt(receipt))
                        }
                    }
                }
                state.phase = .starting
                state.errorMessage = nil
                state.header = nil
                state.hasRetainedAudio = false
                state.isVoiceDetected = false
                state.isVoiceReleasePending = false
                return .send(.appeared)

            case let .failed(message):
                guard !state.isClosing else { return .none }
                state.phase = .failed
                state.errorMessage = message
                state.isVoiceDetected = false
                state.isVoiceReleasePending = false
                return .cancel(id: CancelID.voiceRelease)

            case .disappeared:
                let shouldCancel = state.phase != .saved && !state.isClosing
                let header = state.header
                return .merge(
                    .cancel(id: CancelID.capture),
                    .cancel(id: CancelID.receipts),
                    .cancel(id: CancelID.voiceRelease),
                    .cancel(id: CancelID.autoSave),
                    shouldCancel ? .run { _ in
                        await WatchVoiceRecordingService.shared.cancelInBackground(header)
                    } : .none
                )
            }
        }
    }

    private static func message(for error: Error) -> String {
        switch error as? WatchAudioError {
        case .permissionDenied:
            "Watch 마이크와 iPhone 음성 인식 권한을 확인해 주세요."
        case .invalidAudio: "녹음된 음성이 없어요. 다시 시도해 주세요."
        case .recognitionUnavailable: "iPhone에서 음성을 전사할 수 없어요."
        default: "음성 기록을 진행할 수 없어요. 다시 시도해 주세요."
        }
    }
}

private extension VoiceRecordFeature {
    func handleReceipt(
        state: inout State, receipt: WatchAudioReceipt
    ) -> Effect<Action> {
        guard !state.isClosing, state.phase != .saved else { return .none }
        guard receipt.header.experimentID == state.experimentID,
              receipt.header.recordingID == state.header?.recordingID else { return .none }
        if receipt.savedRecordID == receipt.header.recordingID {
            state.phase = .saved
            state.autoSaveSeconds = 0
            return .cancel(id: CancelID.autoSave)
        }

        if receipt.isCancelled { return .none }
        if let failure = receipt.failure {
            state.phase = .failed
            state.errorMessage = Self.message(for: failure)
            state.hasRetainedAudio = state.hasRetainedAudio
                || !receipt.receivedSequences.isEmpty
            return .cancel(id: CancelID.autoSave)
        }
        if let transcript = receipt.transcript, transcript.isFinal {
            state.transcript = transcript.text
        }
        if state.phase == .awaitingTransfer, let manifest = receipt.manifest,
           manifest.header == receipt.header, manifest.chunkCount > 0,
           receipt.receivedSequences.elementsEqual(0..<manifest.chunkCount) {
            state.phase = .transcribing
        }
        if receipt.isReviewing, receipt.transcript?.isFinal == true,
           state.phase == .transcribing || state.phase == .awaitingTransfer {
            state.phase = .transcript
            state.autoSaveSeconds = 3
            let recordingID = receipt.header.recordingID
            return .run { send in
                for _ in 0..<3 {
                    try await Task.sleep(for: .seconds(1))
                    await send(.autoSaveTick(recordingID))
                }
            }
            .cancellable(id: CancelID.autoSave, cancelInFlight: true)
        }
        return .none
    }
}
