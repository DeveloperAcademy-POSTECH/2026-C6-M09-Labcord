import ComposableArchitecture
import Foundation
import LabcordiOS
import LabcordShared

extension ExperimentSessionFeature {
    var screenSyncReducer: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .clearScreenRecording(id, phase):
                guard state.lastScreenRecording?.id == id,
                      state.lastScreenRecording?.phase == phase,
                      state.currentScreenRecording == nil else { return .none }
                state.lastScreenRecording = nil
                return .none
            case let .gestureGuidePresented(presented):
                state.isGestureGuidePresented = presented
                state.sharedStage = nil
                if state.currentScreenRecording == nil { state.lastScreenRecording = nil }
            case let .sidePanelExpanded(expanded):
                state.isSidePanelExpanded = expanded
                state.sharedStage = nil
            case .beginRemotePreview:
                guard state.isRemotePreview, !state.hasUnsettledScreenWork else { return .none }
                state.isRemotePreview = false
                state.sharedStage = nil
                state.sharedCountdownEndsAt = nil
                state.detail = nil
                return .send(.loadDetail)
            case .pauseTapped, .pause(.delegate(.resumeRequested)),
                 .timer(.editorPresented), .timer(.timerTabSelected), .timer(.timerSaved):
                state.sharedStage = nil
                if state.currentScreenRecording == nil { state.lastScreenRecording = nil }
            default:
                break
            }
            let previous = state.lastScreenRecording
            state.updateScreenRecording(action: action, at: now)
            guard let recording = state.lastScreenRecording, previous != recording,
                  recording.phase == .saved || recording.phase == .cancelled
                    || (recording.phase == .failed && !state.hasUnsettledLocalMedia)
            else { return .none }
            return .run { send in
                try await Task.sleep(for: .seconds(1))
                await send(.clearScreenRecording(recording.id, recording.phase))
            }
        }
    }
}

extension ExperimentSessionFeature.State {
    var isSetupReady: Bool {
        permissions.camera.status == .authorized
            && permissions.microphoneStatus == .authorized
            && permissions.speechRecognitionStatus == .authorized
            && !permissions.isRequesting
            && permissions.issue == nil
            && capture.previewConnector != nil
    }

    var isReady: Bool {
        isSetupReady && detail != nil && timer.isConfigured
    }

    var canCloseSession: Bool {
        timer.isConfigured && timer.pendingSave == nil && !timer.isClosing && !voice.isSaving
            && !pause.isCompleting && !isReturningHome && !hasUnsettledLocalMedia
    }

    var hasUnsettledLocalMedia: Bool {
        voice.phase != .hidden || voice.isSaving || voice.recording != nil
            || capture.photo.isScheduled || capture.photo.isCapturing
            || capture.photo.capturedData != nil || capture.photo.isSaving
            || capture.video.phase != .idle || capture.video.isSaving
    }

    var hasUnsettledScreenWork: Bool {
        watchCommand != nil || watchMediaCommand != nil || watchClosingResources
            || isReturningHome || isLoadingDetail || timer.pendingSave != nil || timer.isClosing
            || pause.isCompleting || hasUnsettledLocalMedia
            || capture.watchPhotoRequest != nil || capture.watchVideoRequest != nil
            || capture.watchReviewRequest != nil || capture.watchStopRequest != nil
    }

    mutating func applyScreen(_ screen: WatchScreenSnapshot, status: ExperimentStatus) {
        if currentScreenRecording == nil { lastScreenRecording = nil }
        isRemotePreview = status != .running
        sharedStage = screen.stage
        sharedCountdownEndsAt = screen.countdownEndsAt
        isPausePresented = screen.stage == .pauseConfirmation
            || screen.stage == .completionConfirmation
        isGestureGuidePresented = screen.stage == .gestures
        timer.isEditorPresented = screen.stage == .timerEditor
        if let seconds = screen.timerDraftSeconds { timer.draftSeconds = seconds }
        if screen.stage == .timers || screen.stage == .timerEditor {
            isSidePanelExpanded = true
            timer.selectedTimerTab = .active
        }
    }

    func screenSnapshot(watchRecording: WatchScreenRecording?) -> WatchScreenSnapshot {
        WatchScreenSnapshot(
            destination: .experiment, experimentID: experimentID, stage: screenStage,
            countdownEndsAt: sharedCountdownEndsAt,
            recording: currentScreenRecording ?? watchRecording ?? lastScreenRecording,
            timerDraftSeconds: screenStage == .timerEditor ? timer.draftSeconds : nil
        )
    }

    var screenStage: WatchScreenSnapshot.Stage {
        if isRemotePreview { return sharedStage ?? .preparation }
        if isPausePresented {
            return sharedStage == .completionConfirmation
                ? .completionConfirmation : .pauseConfirmation
        }
        if isGestureGuidePresented { return .gestures }
        if timer.isEditorPresented { return .timerEditor }
        if !isReady { return permissions.issue == nil ? .preparation : .permission }
        if let sharedStage { return sharedStage }
        if timer.selectedTimerTab == .active, isSidePanelExpanded { return .timers }
        return .active
    }
}
