import ComposableArchitecture
import Foundation
import LabcordShared

@Reducer
struct SortRecordFeature {
    typealias SendCommand = @Sendable (
        WatchExperimentCommand
    ) async throws -> WatchExperimentResponse

    let sendCommand: SendCommand

    @ObservableState
    struct State: Equatable {
        let experimentID: UUID
        var isPhoneResultReady = false
        var isQuerying = false
        var feedback: String?
        var shouldClose = false
    }

    enum Action {
        case phoneResultChanged(Bool)
        case requeryTapped
        case requeryFinished(String?)
        case closeTapped
        case timeout
        case disappeared
    }

    private nonisolated enum CancelID: Hashable, Sendable {
        case autoClose
        case requery
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .phoneResultChanged(ready):
                guard state.isPhoneResultReady != ready else { return .none }
                state.isPhoneResultReady = ready
                guard ready else { return .cancel(id: CancelID.autoClose) }
                state.feedback = nil
                return .run { send in
                    try await Task.sleep(for: .seconds(5))
                    await send(.timeout)
                }
                .cancellable(id: CancelID.autoClose, cancelInFlight: true)

            case .requeryTapped:
                guard !state.isQuerying, !state.shouldClose else { return .none }
                state.isQuerying = true
                state.feedback = nil
                let experimentID = state.experimentID
                return .run { send in
                    do {
                        let response = try await sendCommand(
                            WatchExperimentCommand(operation: .screen)
                        )
                        guard response.phase == .completed, let screen = response.screen else {
                            throw response.error ?? .invalidPayload
                        }
                        let ready = screen.destination == .result
                            && screen.experimentID == experimentID
                        await send(.requeryFinished(
                            ready ? nil : "iPhone에서 이 실험의 결과 화면을 열어 주세요."
                        ))
                    } catch is CancellationError {
                        return
                    } catch {
                        await send(.requeryFinished("iPhone의 화면을 확인하지 못했어요."))
                    }
                }
                .cancellable(id: CancelID.requery, cancelInFlight: true)

            case let .requeryFinished(feedback):
                state.isQuerying = false
                if !state.isPhoneResultReady { state.feedback = feedback }
                return .none

            case .timeout:
                guard state.isPhoneResultReady else { return .none }
                fallthrough
            case .closeTapped:
                guard !state.shouldClose else { return .none }
                state.shouldClose = true
                return .merge(.cancel(id: CancelID.autoClose), .cancel(id: CancelID.requery))

            case .disappeared:
                state.isQuerying = false
                return .merge(.cancel(id: CancelID.autoClose), .cancel(id: CancelID.requery))
            }
        }
    }
}
