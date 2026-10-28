//
//  VoiceRecordingFeature.swift
//  Researchers
//
//  Created by 정홍섭 on 10/28/26.
//

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
        var sessionID = UUID()
        var transcript = ""
        var recording: SpeechRecording?
        var errorMessage: String?
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
        case stopped(UUID, SpeechRecording?)
        case retakeRequested
        case closeRequested
        case errorDismissed
    }

    private nonisolated enum CancelID: Hashable, Sendable {
        case voiceStream
        case voiceStop
    }

    @Dependency(\.speechRecordingClient) var speechRecordingClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .prepareRequested:
                guard state.phase == .hidden else { return .none }
                state.transcript = ""
                state.recording = nil
                state.errorMessage = nil
                state.sessionID = UUID()
                state.phase = .starting
                return .none

            case .overlayAppeared:
                guard state.phase == .starting else { return .none }
                return .send(.startRequested)

            case .startRequested:
                guard state.phase == .starting else { return .none }
                let id = state.sessionID
                return .run { send in
                    do {
                        let events = try await speechRecordingClient.start()
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
                return .none

            case let .startPermissionFailed(id, _):
                guard id == state.sessionID, state.phase == .starting else { return .none }
                state.phase = .hidden
                return .none

            case let .startFailed(id, message):
                guard id == state.sessionID, state.phase == .starting else { return .none }
                state.phase = .hidden
                state.errorMessage = message
                return .none

            case let .event(id, event):
                guard id == state.sessionID else { return .none }
                switch event {
                case let .transcript(text):
                    if state.phase == .recording || state.phase == .stopping {
                        state.transcript = text
                    }
                case let .finished(recording):
                    state.transcript = recording.transcript
                    state.recording = recording
                    state.phase = .finished
                case let .failed(message):
                    state.phase = .hidden
                    state.errorMessage = message
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
                    state.recording = recording
                    state.transcript = recording.transcript
                    state.phase = .finished
                } else {
                    state.phase = .hidden
                    state.errorMessage = "음성 기록을 완료하지 못했습니다. 다시 시도해 주세요."
                }
                return .cancel(id: CancelID.voiceStream)

            case .retakeRequested:
                guard state.phase == .finished else { return .none }
                state.recording = nil
                state.transcript = ""
                state.errorMessage = nil
                state.sessionID = UUID()
                state.phase = .starting
                return .send(.startRequested)

            case .closeRequested:
                guard state.phase != .hidden else { return .none }
                state.phase = .hidden
                state.sessionID = UUID()
                state.transcript = ""
                state.recording = nil
                return .merge(
                    .cancel(id: CancelID.voiceStream),
                    .cancel(id: CancelID.voiceStop),
                    .run { _ in await speechRecordingClient.cancel() }
                )

            case .errorDismissed:
                state.errorMessage = nil
                return .none
            }
        }
    }
}
