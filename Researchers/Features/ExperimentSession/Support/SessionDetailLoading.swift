import ComposableArchitecture
import LabcordiOS
import LabcordShared

extension ExperimentSessionFeature {
    func loadDetail(state: inout State) -> Effect<Action> {
        guard state.isRemotePreview || state.isSetupReady,
              state.detail == nil, !state.isLoadingDetail else { return .none }
        state.isLoadingDetail = true
        state.detailLoadFailed = false
        let experimentID = state.experimentID
        if let requestID = state.watchOpenRequestID {
            let coordinator = PhoneWatchExperimentCoordinator.shared
            do {
                let detail = try coordinator.commitOpenSession(
                    requestID, experimentID: experimentID
                )
                state.watchOpenRequestID = nil
                return .send(.detailLoaded(detail))
            } catch {
                coordinator.finishOpenSession(
                    requestID, error: error as? WatchExperimentError ?? .storageFailed
                )
                return .none
            }
        }
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
