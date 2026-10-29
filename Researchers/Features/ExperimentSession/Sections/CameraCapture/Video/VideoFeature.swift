import ComposableArchitecture
import Foundation
import LabcordiOS
import LabcordShared

@Reducer
struct VideoFeature {
    enum Phase: Equatable {
        case idle
        case starting
        case recording(Date)
        case preview(URL)
    }

    @ObservableState
    struct State: Equatable {
        var phase: Phase = .idle
        var sessionID = UUID()
        var errorMessage: String?
    }

    enum Action: Equatable {
        case prepareRequested
        case recordRequested
        case started(UUID, Date)
        case recorded(UUID, URL)
        case recordingFailed(UUID, String)
        case retakeRequested
        case cancelRequested
        case errorDismissed
        case delegate(Delegate)
    }

    enum Delegate: Equatable {
        case permissionAccessFailed(PermissionKind)
    }

    private nonisolated enum CancelID: Hashable, Sendable {
        case recording
    }

    @Dependency(\.cameraSessionClient) var cameraSessionClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .prepareRequested:
                return .run { _ in
                    try? await cameraSessionClient.prepareVideoRecording()
                }

            case .recordRequested:
                guard state.phase == .idle else { return .none }
                state.sessionID = UUID()
                state.phase = .starting
                let id = state.sessionID
                return .run { send in
                    do {
                        let url = try await cameraSessionClient.recordVideo {
                            Task { await send(.started(id, .now)) }
                        }
                        guard !Task.isCancelled else {
                            await cameraSessionClient.discardVideo(url)
                            return
                        }
                        await send(.recorded(id, url))
                    } catch let error as PermissionAccessError {
                        await send(.delegate(.permissionAccessFailed(error.kind)))
                        await send(.recordingFailed(id, error.localizedDescription))
                    } catch is CancellationError {
                        return
                    } catch {
                        await send(.recordingFailed(id, error.localizedDescription))
                    }
                }
                .cancellable(id: CancelID.recording, cancelInFlight: true)

            case let .started(id, startedAt):
                guard id == state.sessionID, state.phase == .starting else { return .none }
                state.phase = .recording(startedAt)
                return .none

            case let .recorded(id, url):
                guard id == state.sessionID else {
                    return .run { _ in await cameraSessionClient.discardVideo(url) }
                }
                state.phase = .preview(url)
                return .none

            case let .recordingFailed(id, message):
                guard id == state.sessionID else { return .none }
                state.phase = .idle
                state.errorMessage = message
                return .none

            case .retakeRequested:
                guard case let .preview(url) = state.phase else { return .none }
                state.phase = .idle
                return .run { _ in await cameraSessionClient.discardVideo(url) }

            case .cancelRequested:
                let videoURL: URL?
                if case let .preview(url) = state.phase {
                    videoURL = url
                } else {
                    videoURL = nil
                }
                state.phase = .idle
                state.sessionID = UUID()
                return .merge(
                    .cancel(id: CancelID.recording),
                    .run { _ in
                        await cameraSessionClient.cancelVideoRecording()
                        if let videoURL { await cameraSessionClient.discardVideo(videoURL) }
                    }
                )

            case .errorDismissed:
                state.errorMessage = nil
                return .none

            case .delegate:
                return .none
            }
        }
    }
}
