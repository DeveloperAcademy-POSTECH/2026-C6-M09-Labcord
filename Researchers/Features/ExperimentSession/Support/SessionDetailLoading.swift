import ComposableArchitecture
import LabcordiOS

extension ExperimentSessionFeature {
    func loadDetail(state: inout State) -> Effect<Action> {
        guard state.isSetupReady, state.detail == nil,
              !state.isLoadingDetail else { return .none }
        state.isLoadingDetail = true
        state.detailLoadFailed = false
        let experimentID = state.experimentID
        return .run { send in
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
