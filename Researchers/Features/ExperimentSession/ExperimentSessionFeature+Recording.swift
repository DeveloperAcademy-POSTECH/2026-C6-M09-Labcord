import ComposableArchitecture
import Foundation
import LabcordiOS

extension ExperimentSessionFeature {
    func configureSessionDetail(
        _ detail: ExperimentSessionDetail, state: inout State
    ) -> Effect<Action> {
        state.isLoadingDetail = false
        state.detail = detail
        state.voice.contextualStrings = detail.speechContextualStrings
        return .send(
            .timer(
                .configure(
                    mode: detail.mode,
                    timerSeconds: detail.timerSeconds,
                    timers: detail.timers
                )
            )
        )
    }

    func loadDetail(state: inout State) -> Effect<Action> {
        if state.detail != nil {
            state.sessionEntryFailed = false
            state.detailLoadFailed = false
            return enterSessionIfReady(state: &state)
        }
        guard !state.isLoadingDetail else { return .none }
        state.isLoadingDetail = true
        state.detailLoadFailed = false
        let experimentID = state.experimentID
        return .run { send in
            await timerCompletionNotificationClient.cancelForExperiment(experimentID)
            guard let detail = try? await experimentClient.loadDetail(experimentID) else {
                await send(.detailLoadingFailed)
                return
            }
            await send(.detailLoaded(detail))
        }
    }

    func startPhoto(_ id: UUID?, state: inout State) -> Effect<Action> {
        guard state.watchCommand == nil, !state.capture.isWatchPhotoScheduled else {
            return .none
        }
        guard state.voice.phase == .hidden else {
            return .send(.capture(.cancelPhotoGesture))
        }
        return .send(.capture(.photoCaptureRequested(id)))
    }

    func prepareVoiceRecording(state: inout State) -> Effect<Action> {
        guard state.watchCommand == nil else {
            state.voice.errorMessage =
                "Watch의 실험 중단 또는 종료를 처리 중이에요. 완료 후 다시 시도해주세요."
            return .none
        }
        guard state.detail != nil else {
            if state.isLoadingDetail {
                state.voice.errorMessage = "실험 정보를 불러오고 있어요. 잠시 후 다시 시도해 주세요."
            } else {
                state.detailLoadFailed = true
            }
            return .none
        }
        guard !state.capture.isWatchPhotoScheduled else {
            state.voice.errorMessage = "Watch 사진 촬영이 끝난 뒤 녹음해주세요."
            return .none
        }
        guard state.voice.phase == .hidden, !state.voice.hasRecordingFailure,
              state.capture.isCameraViewVisible,
              !state.capture.isCapturingPhoto,
              state.capture.capturedPhotoData == nil,
              state.capture.videoPhase == .idle else { return .none }
        return .merge(
            .send(.capture(.cancelPhotoGesture)),
            .send(.voice(.prepareRequested))
        )
    }
}
