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
    typealias Kind = WatchRemoteIntentRequest.Kind

    static let shared = PhoneIntentRuntime()
    let store = Store(initialState: AppFeature.State()) { AppFeature() }
    private let logger = Logger(subsystem: "Labcord", category: "PhoneIntent")
    private var isPerforming = false
    private static let timeout: TimeInterval = 3

    /// 세 기록 단축어 모두 Watch 실험 화면에 전달해 Watch의 기록 흐름으로 진행합니다.
    func perform(_ kind: Kind) async throws -> String {
        logger.notice("Intent invoked: \(String(describing: kind), privacy: .public)")
        guard !isPerforming else {
            logger.error("Intent rejected: previous request is still running")
            throw PhoneIntentError.busy
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(Self.timeout))
        let expiresAt = Date.now.addingTimeInterval(Self.timeout)
        isPerforming = true
        defer { isPerforming = false }
        if let id = store.path.ids.last,
           let practice = store.path[id: id, case: \.gesturePractice] {
            return recognizePracticeGesture(kind, id: id, practice: practice)
        }
        guard let id = store.path.ids.last,
              let initial = store.path[id: id, case: \.session] else {
            logger.notice("Intent rejected: no experiment screen")
            throw PhoneIntentError.openExperiment
        }
        let screen = PhoneWatchExperimentCoordinator.shared.currentScreen
        guard screen.recordingExperimentID == initial.experimentID,
              let gestureSession = screen.gestureSession else {
            throw PhoneIntentError.openExperiment
        }
        let request = WatchRemoteIntentRequest(
            requestID: UUID(), experimentID: initial.experimentID, expiresAt: expiresAt,
            kind: kind, gestureSession: gestureSession
        )
        return try await requestWatch(request, from: id, deadline: deadline)
    }

    func resolveWatchGesture(_ kind: Kind) -> WatchGestureRouteReply.Route? {
        guard let id = store.path.ids.last else { return nil }
        if let practice = store.path[id: id, case: \.gesturePractice] {
            guard UIApplication.shared.applicationState == .active,
                  practice.device == .appleWatch else { return nil }
            _ = recognizePracticeGesture(kind, id: id, practice: practice)
            return .practice
        }
        let coordinator = PhoneWatchExperimentCoordinator.shared
        let screen = coordinator.currentScreen
        guard UIApplication.shared.applicationState != .background,
              let session = store.path[id: id, case: \.session],
              screen.recordingExperimentID == session.experimentID,
              screen.epoch != nil, let gestureSession = screen.gestureSession else { return nil }
        return .experiment(
            screen, screenAge: Date.now.timeIntervalSince(gestureSession.startedAt),
            summary: coordinator.runningGestureExperiment(session.experimentID)
        )
    }

    /// 제스처 연습 화면의 Apple Watch 탭에서는 기록 없이 인식 결과만 표시합니다.
    /// iPhone 탭에서는 카메라 손동작으로 연습하므로 단축어 요청을 조용히 무시합니다.
    private func recognizePracticeGesture(
        _ kind: Kind, id: StackElementID, practice: GesturePracticeFeature.State
    ) -> String {
        guard practice.device == .appleWatch else {
            logger.info("Practice gesture ignored: iPhone tab is selected")
            return ""
        }
        store.send(.path(.element(
            id: id, action: .gesturePractice(.watchGestureRecognized(kind.practiceGesture))
        )))
        logger.info("Practice gesture recognized: \(String(describing: kind), privacy: .public)")
        return "제스처를 인식했어요."
    }

    private func waitForSession(
        _ request: WatchRemoteIntentRequest, from id: StackElementID,
        connection: WCSession, deadline: ContinuousClock.Instant
    ) async throws {
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            let screen = PhoneWatchExperimentCoordinator.shared.currentScreen
            guard store.path.ids.last == id,
                  let session = store.path[id: id, case: \.session],
                  screen.recordingExperimentID == request.experimentID,
                  session.experimentID == request.experimentID,
                  screen.gestureSession == request.gestureSession else {
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
            case .ready:
                let state = WatchConnectivityState(connection)
                if state.canTransfer && state.reachable { return }
            case .busy:
                logger.error("Intent readiness rejected: session command is still running")
                throw PhoneIntentError.busy
            case .failed:
                throw PhoneIntentError.busy
            case .wait: break
            }
            let next = ContinuousClock.now.advanced(by: .milliseconds(50))
            try await Task.sleep(until: min(deadline, next), clock: .continuous)
        }
        WatchConnectivityDiagnostics.state(connection, event: "intentUnavailable")
        throw PhoneIntentError.timedOut
    }

    private func requestWatch(
        _ request: WatchRemoteIntentRequest, from pathID: StackElementID,
        deadline: ContinuousClock.Instant
    ) async throws -> String {
        guard WCSession.isSupported() else {
            logger.error("Watch request rejected: WatchConnectivity is unsupported")
            throw PhoneIntentError.watchUnavailable
        }
        @Dependency(\.watchConnectivitySession) var connectivity
        connectivity.activate()
        let session = WCSession.default
        let id = request.requestID.uuidString
        try await waitForSession(request, from: pathID, connection: session, deadline: deadline)
        try Task.checkCancellation()
        guard store.path.ids.last == pathID,
              PhoneWatchExperimentCoordinator.shared.currentScreen.gestureSession
                == request.gestureSession else { throw PhoneIntentError.contextChanged }
        let data = try JSONEncoder().encode(request)
        let responseKey = WatchRemoteIntentResponse.messageKey
        let response = try await WatchReply.wait(
            for: request.requestID, until: deadline
        ) { finish in
            WatchConnectivityDiagnostics.event("intent.sent", id: id, bytes: data.count)
            session.sendMessage([WatchRemoteIntentRequest.messageKey: data]) { @Sendable reply in
                let data = reply[responseKey] as? Data
                Task { @MainActor in finish(.success(data)) }
            } errorHandler: { @Sendable error in
                WatchConnectivityDiagnostics.failure("intent.sendFailed", id: id, error: error)
                let failure = (error as? WCError)?.code == .notReachable
                    ? PhoneIntentError.watchUnavailable : .unknown
                Task { @MainActor in finish(.failure(failure)) }
            }
        }
        WatchConnectivityDiagnostics.event(
            response.accepted ? "intent.accepted" : "intent.rejected", id: id
        )
        guard response.accepted else { throw PhoneIntentError.rejected(response.message) }
        return response.message
    }
}

private extension WatchRemoteIntentRequest.Kind {
    var practiceGesture: PracticeGesture {
        switch self {
        case .voice: .voice
        case .photo: .photo
        case .video: .video
        }
    }
}

private enum PhoneIntentError: LocalizedError {
    case busy, openExperiment, contextChanged, watchUnavailable, timedOut, unknown
    case rejected(String)

    var errorDescription: String? {
        switch self {
        case .busy: "다른 단축어 요청을 처리 중이에요."
        case .openExperiment: "iPhone에서 진행 중인 실험을 먼저 열어주세요."
        case .contextChanged: "실험 화면이 바뀌었어요. 현재 상태를 확인해주세요."
        case .watchUnavailable: "Watch 앱을 열고 iPhone 연결을 확인해주세요."
        case .timedOut: "3초 안에 응답을 받지 못했어요. 앱에서 실행 여부를 확인해 주세요."
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
        for requestID: UUID, until deadline: ContinuousClock.Instant,
        send: (@escaping @MainActor (Result<Data?, PhoneIntentError>) -> Void) -> Void
    ) async throws -> WatchRemoteIntentResponse {
        let gate = WatchReply()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !gate.cancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                guard ContinuousClock.now < deadline else {
                    continuation.resume(throwing: PhoneIntentError.timedOut)
                    return
                }
                gate.continuation = continuation
                gate.timeout = Task { @MainActor in
                    try? await Task.sleep(until: deadline, clock: .continuous)
                    guard !Task.isCancelled else { return }
                    WatchConnectivityDiagnostics.failure(
                        "intent.timeout", id: requestID.uuidString,
                        error: WatchExperimentError.deliveryTimeout
                    )
                    gate.finish(.failure(.timedOut), requestID: requestID)
                }
                send { result in
                    let isTimely = ContinuousClock.now < deadline
                    gate.finish(isTimely ? result : .failure(.timedOut), requestID: requestID)
                }
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

    private func finish(_ result: Result<Data?, PhoneIntentError>, requestID: UUID) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel()
        if case let .failure(error) = result {
            continuation.resume(throwing: error)
            return
        }
        guard case let .success(data?) = result,
              let response = try? JSONDecoder().decode(WatchRemoteIntentResponse.self, from: data),
              response.requestID == requestID else {
            WatchConnectivityDiagnostics.failure(
                "intent.invalidReply", id: requestID.uuidString,
                error: WatchExperimentError.invalidPayload
            )
            continuation.resume(throwing: PhoneIntentError.unknown)
            return
        }
        continuation.resume(returning: response)
    }
}
