import ComposableArchitecture
import Foundation
import LabcordShared

nonisolated enum WatchIntentRuntimeError: Error, LocalizedError, Equatable {
    case appNotActive
    case notReady
    case busy
    case selectExperiment
    case noRunningExperiment
    case permissionRequired
    case contextChanged
    case interrupted
    case photoResultPending
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
        case .photoResultPending:
            "사진 요청 결과를 아직 확인하지 못했어요. 다시 요청하기 전에 앱에서 상태를 확인해주세요."
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
            throw WatchIntentRuntimeError.notReady
        }
        if kind == .voice, let stop = localVoiceStop(state: state) { return stop }
        return try liveAction(for: kind, state: state)
    }

    static func localVoiceStop(
        state: WatchExperimentFeature.State
    ) -> WatchExperimentFeature.Action? {
        guard state.screen != .gestures, let experimentID = state.selectedID else { return nil }
        let voices = state.recording.records.values.filter {
            $0.experimentID == experimentID && $0.kind == .voice && $0.phase == .capturing
        }
        guard voices.count == 1 else { return nil }
        return .recording(.stop(voices[0].id))
    }

    private static func liveAction(
        for kind: WatchRecordPresentation.Kind, state: WatchExperimentFeature.State
    ) throws -> WatchExperimentFeature.Action {
        guard state.hasRestoredPending, !state.pendingRecoveryFailed,
              !state.screenRecoveryNeeded else {
            throw WatchIntentRuntimeError.notReady
        }
        guard state.pending == nil, !state.isPreparingInterruption else {
            throw WatchIntentRuntimeError.busy
        }
        guard !state.phoneRecordingBlocksCapture else { throw WatchIntentRuntimeError.busy }
        guard state.screen == .experiment || state.screen == .timers else {
            throw WatchIntentRuntimeError.busy
        }
        guard let id = state.selectedID else { throw WatchIntentRuntimeError.selectExperiment }
        guard state.snapshot?.experiment.status == .running else {
            throw WatchIntentRuntimeError.noRunningExperiment
        }
        guard state.recording.isIntegrated else { throw WatchIntentRuntimeError.notReady }
        let unsettled = state.recording.records.values.filter {
            state.recording.blocksNewCapture($0) && ($0.experimentID == id || $0.phase == .starting
                || $0.phase == .capturing || $0.phase == .stopping)
        }
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
