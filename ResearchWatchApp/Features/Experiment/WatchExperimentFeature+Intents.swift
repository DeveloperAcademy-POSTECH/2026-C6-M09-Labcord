import ComposableArchitecture
import Foundation
import LabcordShared

struct WatchGesturePractice: Equatable {
    var voiceRecording = false
    var videoRecording = false
    var feedback: String?
}

nonisolated enum WatchIntentRuntimeError: Error, LocalizedError, Equatable {
    case appNotActive
    case notReady
    case busy
    case selectExperiment
    case noRunningExperiment
    case permissionRequired
    case contextChanged
    case interrupted
    case requestRejected(String)

    var errorDescription: String? {
        switch self {
        case .appNotActive: "Watch에서 Labcord를 열고 다시 실행해주세요."
        case .notReady: "실험 상태를 확인하지 못했어요. 앱에서 연결·요청 결과를 확인해주세요."
        case .busy: "기록이나 요청을 처리 중이에요. 앱에서 결과를 확인한 뒤 다시 실행해주세요."
        case .selectExperiment: "Watch 앱에서 기록할 실험을 먼저 선택해주세요."
        case .noRunningExperiment: "선택한 실험이 진행 중이 아니에요. 앱에서 상태를 확인해주세요."
        case .permissionRequired: "Watch 앱에서 마이크 권한을 먼저 허용해주세요."
        case .contextChanged: "화면이나 실험이 바뀌었어요. 현재 화면을 확인하고 다시 실행해주세요."
        case .interrupted: "요청이 중단됐어요. 앱에서 상태를 확인해주세요."
        case let .requestRejected(message): message
        }
    }
}

enum WatchIntentRouting {
    static func action(
        for kind: WatchRecordPresentation.Kind, state: WatchExperimentFeature.State
    ) throws -> WatchExperimentFeature.Action {
        guard state.isVisible, state.streamID != nil else {
            throw WatchIntentRuntimeError.notReady
        }
        if state.screen == .gestures {
            guard state.pending == nil, !state.isPreparingInterruption,
                  !state.recording.records.values.contains(where: { !$0.isSettled }) else {
                throw WatchIntentRuntimeError.busy
            }
            return .practiceRecord(kind)
        }
        if kind == .voice, let stop = localVoiceStop(state: state) { return stop }
        return try liveAction(for: kind, state: state)
    }

    static func localVoiceStop(
        state: WatchExperimentFeature.State
    ) -> WatchExperimentFeature.Action? {
        guard state.screen != .gestures else { return nil }
        let voices = state.recording.records.values.filter {
            $0.kind == .voice && $0.phase == .capturing
        }
        guard voices.count == 1 else { return nil }
        return .recording(.stop(voices[0].id))
    }

    private static func liveAction(
        for kind: WatchRecordPresentation.Kind, state: WatchExperimentFeature.State
    ) throws -> WatchExperimentFeature.Action {
        guard state.hasRestoredPending, !state.pendingRecoveryFailed else {
            throw WatchIntentRuntimeError.notReady
        }
        guard state.pending == nil, !state.isPreparingInterruption else {
            throw WatchIntentRuntimeError.busy
        }
        guard state.screen == .experiment || state.screen == .timers else {
            throw WatchIntentRuntimeError.busy
        }
        guard let id = state.selectedID else { throw WatchIntentRuntimeError.selectExperiment }
        guard state.snapshot?.experiment.status == .running else {
            throw WatchIntentRuntimeError.noRunningExperiment
        }
        guard state.recording.isIntegrated else { throw WatchIntentRuntimeError.notReady }
        let unsettled = state.recording.records.values.filter { !$0.isSettled }
        if let record = unsettled.first {
            guard unsettled.count == 1, record.experimentID == id,
                  record.kind == kind, kind == .video, record.phase == .capturing else {
                throw WatchIntentRuntimeError.busy
            }
            return .recording(.stop(record.id))
        }
        return .recordTapped(kind)
    }
}

extension WatchExperimentFeature {
    func practiceRecord(
        _ kind: WatchRecordPresentation.Kind, state: inout State
    ) -> Effect<Action> {
        guard state.screen == .gestures, state.pending == nil,
              !state.isPreparingInterruption,
              !state.recording.records.values.contains(where: { !$0.isSettled }) else {
            state.practice.feedback = "진행 중인 기록을 먼저 확인해주세요. 연습 입력은 적용하지 않았어요."
            return .none
        }
        switch kind {
        case .voice:
            state.practice.voiceRecording.toggle()
            state.practice.feedback = state.practice.voiceRecording
                ? "음성 시작 연습 성공" : "음성 중지 연습 성공"
        case .photo:
            state.practice.feedback = "사진 촬영 연습 성공"
        case .video:
            state.practice.videoRecording.toggle()
            state.practice.feedback = state.practice.videoRecording
                ? "영상 시작 연습 성공" : "영상 중지 연습 성공"
        }
        return .none
    }
}
