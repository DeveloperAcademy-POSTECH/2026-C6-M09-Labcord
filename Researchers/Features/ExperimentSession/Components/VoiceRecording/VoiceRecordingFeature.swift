import ComposableArchitecture
import Foundation
import LabcordiOS

@Reducer
struct VoiceRecordingFeature {
    enum Phase: Equatable {
        case hidden
        case starting
        case recording
        case stopping
        case finished
    }

    @ObservableState
    struct State: Equatable {
        var phase: Phase = .hidden
        var captureStartRequested = false
        var sessionID = UUID()
        var transcript = ""
        var hasRecordingFailure = false
        var recording: SpeechRecording?
        var errorMessage: String?
        let experimentID: UUID
        var recordID: UUID?
        var recordedAt: Date?
        var isSaving = false
        var isSessionClosing = false
        var saveError: String?
        var isAutoSavePending = false
        var lastSavedRecordID: UUID?
        var speechUnits: [String] = []
        var contextualStrings: [String] = []
        var phoneticReplacements: [String: String] = [:]
        var languageModelHint: SpeechLanguageModelHint?
        var shouldSaveOnStop = false
        var isPauseCancellationPending = false
    }

    enum Action: Equatable {
        case prepareRequested
        case overlayAppeared
        case startRequested
        case started(UUID)
        case startPermissionFailed(UUID, PermissionKind)
        case startFailed(UUID, String)
        case event(UUID, SpeechRecordingEvent)
        case stopRequested
        case stopAndSaveRequested
        case discardForWatchPause
        case watchPauseDiscarded(UUID)
        case stopped(UUID, SpeechRecording?)
        case retakeRequested
        case saveRequested
        case autoSaveElapsed(UUID)
        case saved(UUID)
        case saveFailed(UUID, String)
        case vocabularyLoaded(SpeechSessionVocabulary)
        case languageModelHintLoaded(SpeechLanguageModelHint?)
        case cancelCleanupFailed(String)
        case closeRequested
        case errorDismissed
    }

    nonisolated enum CancelID: Hashable, Sendable {
        case voiceStream
        case voiceStop
        case autoSave
        case save
    }

    @Dependency(\.speechRecordingClient) var speechRecordingClient
    @Dependency(\.experimentClient) var experimentClient
    @Dependency(\.date.now) var now
    @Dependency(\.uuid) var uuid

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            if state.isSessionClosing, action.isBlockedDuringSessionClose { return .none }
            switch action {
            case .discardForWatchPause, .watchPauseDiscarded:
                return reduceWatchPause(state: &state, action: action)

            case .stopAndSaveRequested:
                guard state.phase != .hidden else { return .none }
                state.shouldSaveOnStop = true
                if state.phase == .finished { return saveAudio(state: &state) }
                return .send(.stopRequested)

            case .prepareRequested:
                return prepareRecording(state: &state)

            case .overlayAppeared:
                guard state.phase == .starting else { return .none }
                return .send(.startRequested)

            case .startRequested:
                guard state.phase == .starting, !state.captureStartRequested else { return .none }
                state.captureStartRequested = true
                let id = state.sessionID
                let experimentID = state.experimentID
                let speechUnits = state.speechUnits
                let contextualStrings = state.contextualStrings
                let phoneticReplacements = state.phoneticReplacements
                let languageModelHint = state.languageModelHint
                return .run { send in
                    do {
                        let events = try await speechRecordingClient.start(
                            experimentID: experimentID, contextualStrings: contextualStrings,
                            phoneticReplacements: phoneticReplacements, units: speechUnits,
                            languageModelHint: languageModelHint
                        )
                        await send(.started(id))
                        for await event in events {
                            await send(.event(id, event))
                        }
                    } catch is CancellationError {
                        return
                    } catch let error as PermissionAccessError {
                        await send(.startPermissionFailed(id, error.kind))
                    } catch {
                        await send(.startFailed(id, error.localizedDescription))
                    }
                }
                .cancellable(id: CancelID.voiceStream, cancelInFlight: true)

            case let .started(id):
                guard id == state.sessionID, state.phase == .starting else { return .none }
                state.phase = .recording
                state.recordedAt = now
                if state.shouldSaveOnStop { return .send(.stopRequested) }
                return .none

            case let .startPermissionFailed(id, _):
                guard id == state.sessionID, state.phase == .starting else { return .none }
                state.phase = .hidden
                return .none

            case let .startFailed(id, message):
                guard id == state.sessionID, state.phase == .starting else { return .none }
                state.phase = .hidden
                state.errorMessage = message
                state.hasRecordingFailure = true
                return .none

            case let .event(id, event):
                guard id == state.sessionID else { return .none }
                switch event {
                case let .transcript(text):
                    if state.phase == .recording || state.phase == .stopping {
                        state.transcript = text
                    }
                case .transcriptionUnavailable:
                    state.errorMessage = "음성 전사가 중단됐어요. 녹음은 계속됩니다."
                case let .finished(recording):
                    guard state.phase == .recording || state.phase == .stopping else {
                        return .none
                    }
                    return finishRecording(recording, state: &state)
                case let .interrupted(recording, message):
                    return interrupted(recording, message: message, state: &state)
                case let .failed(message):
                    state.phase = .hidden
                    state.errorMessage = message
                    state.hasRecordingFailure = true
                    resetReview(state: &state)
                    return .none
                }
                return .none

            case .stopRequested:
                guard state.phase == .recording else { return .none }
                state.phase = .stopping
                let id = state.sessionID
                return .run { send in
                    let recording = await speechRecordingClient.stop()
                    await send(.stopped(id, recording))
                }
                .cancellable(id: CancelID.voiceStop, cancelInFlight: true)

            case let .stopped(id, recording):
                guard id == state.sessionID, state.phase == .stopping else { return .none }
                if let recording {
                    return finishStopped(recording, state: &state)
                }
                state.phase = .hidden
                state.errorMessage = "녹음하지 못했어요. 하단 마이크 버튼을 눌러 다시 녹음해 주세요."
                state.hasRecordingFailure = true
                resetReview(state: &state)
                return .cancel(id: CancelID.voiceStream)

            case .retakeRequested:
                guard state.phase == .finished, !state.isSaving else { return .none }
                resetReview(state: &state)
                state.errorMessage = nil
                state.sessionID = uuid()
                state.captureStartRequested = false
                state.phase = .starting
                return .concatenate(
                    .cancel(id: CancelID.autoSave),
                    .run { send in
                        await speechRecordingClient.cancel()
                        await send(.startRequested)
                    }
                )

            case .saveRequested:
                return saveAudio(state: &state)

            case let .autoSaveElapsed(id):
                guard state.recordID == id, state.isAutoSavePending else { return .none }
                return saveAudio(state: &state)

            case let .saved(id):
                guard state.recordID == id else { return .none }
                state.lastSavedRecordID = id
                state.phase = .hidden
                resetReview(state: &state)
                return .none

            case let .saveFailed(id, message):
                guard state.recordID == id else { return .none }
                state.isSaving = false
                state.saveError = message
                return .none

            case let .vocabularyLoaded(vocabulary):
                state.contextualStrings = vocabulary.contextualStrings
                state.phoneticReplacements = vocabulary.replacements
                return .none

            case let .languageModelHintLoaded(hint):
                state.languageModelHint = hint
                return .none

            case let .cancelCleanupFailed(message):
                state.errorMessage = message
                return .none

            case .closeRequested:
                guard state.phase != .hidden || state.hasRecordingFailure else { return .none }
                let savingRecordID = state.isSaving ? state.recordID : nil
                let sourceURL = state.recording?.audioURL
                let experimentID = state.experimentID
                state.phase = .hidden
                state.sessionID = uuid()
                state.hasRecordingFailure = false
                resetReview(state: &state)
                return .concatenate(
                    .cancel(id: CancelID.voiceStream),
                    .cancel(id: CancelID.voiceStop),
                    .cancel(id: CancelID.autoSave),
                    .cancel(id: CancelID.save),
                    .run { send in
                        await speechRecordingClient.cancel()
                        guard let savingRecordID, let sourceURL else { return }
                        do {
                            try await experimentClient.cancelAudioSave(
                                experimentID, savingRecordID, sourceURL
                            )
                        } catch {
                            await send(.cancelCleanupFailed(error.localizedDescription))
                        }
                    }
                )

            case .errorDismissed:
                state.errorMessage = nil
                state.hasRecordingFailure = false
                return .none
            }
        }
    }
}

private extension VoiceRecordingFeature.Action {
    var isBlockedDuringSessionClose: Bool {
        switch self {
        case .prepareRequested, .retakeRequested, .closeRequested: true
        default: false
        }
    }
}
