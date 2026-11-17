import ComposableArchitecture
import Foundation
import LabcordiOS
import LabcordShared
import Observation
import OSLog
import UIKit
import WatchConnectivity

@MainActor
@Observable
final class PhoneIntentRuntime {
    enum Kind { case voice, photo, video }

    static let shared = PhoneIntentRuntime()
    let store = Store(initialState: AppFeature.State()) { AppFeature() }
    private let logger = Logger(subsystem: "Labcord", category: "PhoneIntent")
    private var isPerforming = false

    /// 세 기록 단축어 모두 Watch 실험 화면에 전달해 Watch의 기록 흐름으로 진행합니다.
    func perform(_ kind: Kind) async throws -> String {
        guard !isPerforming else {
            logger.error("Intent rejected: previous request is still running")
            throw PhoneIntentError.busy
        }
        isPerforming = true
        defer { isPerforming = false }
        guard let id = store.path.ids.last,
              let initial = store.path[id: id, case: \.session] else {
            throw PhoneIntentError.openExperiment
        }
        let session = try await waitForSession(id: id, experimentID: initial.experimentID)
        return try await requestWatch(kind, experimentID: session.experimentID)
    }

    private func waitForSession(
        id: StackElementID, experimentID: UUID
    ) async throws -> ExperimentSessionFeature.State {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            guard store.path.ids.last == id,
                  let session = store.path[id: id, case: \.session],
                  session.experimentID == experimentID else {
                throw PhoneIntentError.contextChanged
            }
            let readiness = PhoneIntentReadiness.decide(.init(
                active: UIApplication.shared.applicationState == .active && store.watchIsActive,
                detailReady: session.detail != nil,
                cameraNeeded: false,
                cameraReady: false,
                cameraFailed: false,
                busy: session.isRemotePreview || session.pause.isCompleting
                    || session.isReturningHome
                    || store.watchRequestID != nil || session.watchCommand != nil
                    || session.watchMediaCommand != nil
            ))
            switch readiness {
            case .ready: return session
            case .busy:
                logger.error("Intent readiness rejected: session command is still running")
                throw PhoneIntentError.busy
            case .failed:
                throw PhoneIntentError.busy
            case .wait: try await Task.sleep(for: .milliseconds(50))
            }
        }
        throw PhoneIntentError.openExperiment
    }

    private func requestWatch(_ kind: Kind, experimentID: UUID) async throws -> String {
        guard WCSession.isSupported() else {
            logger.error("Watch request rejected: WatchConnectivity is unsupported")
            throw PhoneIntentError.watchUnavailable
        }
        let activated = WCSession.default.activationState == .activated
        let reachable = WCSession.default.isReachable
        guard activated, reachable else {
            logger.error("Watch request rejected: activated=\(activated) reachable=\(reachable)")
            throw PhoneIntentError.watchUnavailable
        }
        let request = WatchRemoteIntentRequest(
            requestID: UUID(), experimentID: experimentID,
            expiresAt: .now.addingTimeInterval(3), kind: kind.remoteKind
        )
        let data = try JSONEncoder().encode(request)
        let responseKey = WatchRemoteIntentResponse.messageKey
        let response = try await WatchReply.wait(for: request.requestID) { finish in
            WCSession.default.sendMessage(
                [WatchRemoteIntentRequest.messageKey: data]
            ) { @Sendable reply in
                let data = reply[responseKey] as? Data
                Task { @MainActor in finish(data) }
            } errorHandler: { @Sendable _ in
                Task { @MainActor in finish(nil) }
            }
        }
        guard response.accepted else {
            logger.error("Watch request rejected: \(response.message, privacy: .public)")
            throw PhoneIntentError.rejected(response.message)
        }
        logger.info("Watch request accepted: \(String(describing: kind), privacy: .public)")
        return response.message
    }
}

private extension PhoneIntentRuntime.Kind {
    var remoteKind: WatchRemoteIntentRequest.Kind {
        switch self {
        case .voice: .voice
        case .photo: .photo
        case .video: .video
        }
    }
}

private enum PhoneIntentError: LocalizedError {
    case busy, openExperiment, contextChanged, watchUnavailable, unknown
    case rejected(String)

    var errorDescription: String? {
        switch self {
        case .busy: "다른 단축어 요청을 처리 중이에요."
        case .openExperiment: "iPhone에서 진행 중인 실험을 먼저 열어주세요."
        case .contextChanged: "실험 화면이 바뀌었어요. 현재 상태를 확인해주세요."
        case .watchUnavailable: "Watch 앱을 열고 iPhone 연결을 확인해주세요."
        case .unknown: "요청 결과를 확인하지 못했어요. 앱에서 확인한 뒤 다시 실행해주세요."
        case let .rejected(message): message
        }
    }
}

@MainActor
private final class WatchReply {
    private var continuation: CheckedContinuation<WatchRemoteIntentResponse, Error>?
    private var timeout: Task<Void, Never>?
    private var cancelled = false

    static func wait(
        for requestID: UUID,
        send: (@escaping @MainActor (Data?) -> Void) -> Void
    ) async throws -> WatchRemoteIntentResponse {
        let gate = WatchReply()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !gate.cancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                gate.continuation = continuation
                gate.timeout = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(4))
                    guard !Task.isCancelled else { return }
                    gate.finish(nil, requestID: requestID)
                }
                send { data in gate.finish(data, requestID: requestID) }
            }
        } onCancel: {
            Task { @MainActor in gate.cancel() }
        }
    }

    private func cancel() {
        cancelled = true
        timeout?.cancel()
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }

    private func finish(_ data: Data?, requestID: UUID) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel()
        guard let data,
              let response = try? JSONDecoder().decode(WatchRemoteIntentResponse.self, from: data),
              response.requestID == requestID else {
            continuation.resume(throwing: PhoneIntentError.unknown)
            return
        }
        continuation.resume(returning: response)
    }
}
