import ComposableArchitecture
import LabcordiOS

extension ExperimentSessionFeature {
    func loadDetail(state: inout State) -> Effect<Action> {
        guard state.isRemotePreview || state.isSetupReady,
              state.detail == nil, !state.isLoadingDetail else { return .none }
        state.isLoadingDetail = true
        state.detailLoadFailed = false
        let experimentID = state.experimentID
        let preview = state.isRemotePreview
        return .run { send in
            if preview {
                guard let detail = try? await experimentClient.watchState(experimentID)?.detail
                else {
                    await send(.detailLoadingFailed)
                    return
                }
                await send(.detailLoaded(detail))
                return
            }
            await timerCompletionNotificationClient.cancelForExperiment(experimentID)
            guard let detail = try? await experimentClient.enterSessionAndLoadDetail(
                experimentID
            ) else {
                await send(.detailLoadingFailed)
                return
            }
            await send(.detailLoaded(detail))
        }
    }
}
