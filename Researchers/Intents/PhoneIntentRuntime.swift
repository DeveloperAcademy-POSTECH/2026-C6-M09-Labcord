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
    var pendingResolutionRequested = false
    var pendingResolutionFailed = false
    private var pendingURL: URL {
        URL.applicationSupportDirectory.appending(path: "PhoneIntentPendingVoice/request.json")
    }

    func releasePendingVoice() {
        guard !isPerforming else { return }
        do {
            if FileManager.default.fileExists(atPath: pendingURL.path) {
                try FileManager.default.removeItem(at: pendingURL)
            }
        } catch { pendingResolutionFailed = true }
    }

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
        let session = try await waitForSession(
            id: id, experimentID: initial.experimentID, kind: kind
        )

        if kind == .voice { return try await requestWatchVoice(session.experimentID) }
        guard session.capture.isCameraViewVisible,
              session.capture.previewConnector != nil,
              !session.capture.isCameraSwitching,
              !session.capture.isCapturingPhoto,
              !session.capture.isPhotoCaptureScheduled,
              session.capture.capturedPhotoData == nil,
              session.capture.photo.requestedRecordID == nil,
              !session.capture.photo.requiresExternalConfirmation,
              session.capture.videoPhase == .idle,
              session.capture.video.requestedRecordID == nil,
              !session.capture.video.requiresExternalConfirmation,
              session.voice.phase == .hidden else {
            logCaptureState(session, stage: "beforeRequest")
            throw PhoneIntentError.cameraBusy
        }
        let requestID = UUID()
        logger.info("Capture request submitted: id=\(requestID, privacy: .public)")
        let action: ExperimentSessionFeature.Action = kind == .photo
            ? .capture(.photo(.shortcutCaptureRequested(requestID)))
            : .capture(.video(.shortcutRecordRequested(requestID)))
        store.send(.path(.element(id: id, action: .session(action))))
        return try await waitForCaptureAcceptance(
            id: id, experimentID: session.experimentID, kind: kind, requestID: requestID
        )
    }

    private func waitForCaptureAcceptance(
        id: StackElementID, experimentID: UUID, kind: Kind, requestID: UUID
    ) async throws -> String {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            guard UIApplication.shared.applicationState == .active,
                  store.path.ids.last == id,
                  let current = store.path[id: id, case: \.session],
                  current.experimentID == experimentID else {
                logger.error("Capture context changed: id=\(requestID, privacy: .public)")
                throw PhoneIntentError.contextChanged
            }
            if kind == .photo, PhoneIntentReadiness.photoRequestAccepted(
                requestID: requestID,
                currentRequestID: current.capture.photo.requestedRecordID,
                isScheduled: current.capture.isPhotoCaptureScheduled,
                isCapturing: current.capture.isCapturingPhoto,
                hasCapturedData: current.capture.capturedPhotoData != nil
            ) {
                logger.info("Photo request accepted: id=\(requestID, privacy: .public)")
                return "iPhone에 사진 촬영을 요청했어요. 저장 결과는 앱에서 확인해주세요."
            }
            if kind == .video, current.capture.video.requestedRecordID == requestID,
               current.capture.videoPhase != .idle {
                return "iPhone에 영상 녹화를 요청했어요. 저장 결과는 앱에서 확인해주세요."
            }
            if current.capture.cameraErrorMessage != nil {
                logCaptureState(current, stage: "afterRequest")
                throw PhoneIntentError.cameraBusy
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        logger.error("Capture acceptance timed out: id=\(requestID, privacy: .public)")
        throw PhoneIntentError.unknown
    }

    private func waitForSession(
        id: StackElementID, experimentID: UUID, kind: Kind
    ) async throws -> ExperimentSessionFeature.State {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            guard store.path.ids.last == id,
                  let session = store.path[id: id, case: \.session],
                  session.experimentID == experimentID else {
                throw PhoneIntentError.contextChanged
            }
            let cameraNeeded = kind != .voice
            let readiness = PhoneIntentReadiness.decide(.init(
                active: UIApplication.shared.applicationState == .active && store.watchIsActive,
                detailReady: session.detail != nil,
                cameraNeeded: cameraNeeded,
                cameraReady: session.capture.isCameraViewVisible
                    && session.capture.previewConnector != nil,
                cameraFailed: cameraNeeded && session.capture.cameraErrorMessage != nil,
                busy: session.isRemotePreview || session.pause.isCompleting
                    || session.isReturningHome
                    || (cameraNeeded && PhoneWatchAudioService.shared.hasUnsettledRecording(
                        in: session.experimentID
                    ))
                    || store.watchRequestID != nil || session.watchCommand != nil
                    || session.watchMediaCommand != nil
            ))
            switch readiness {
            case .ready: return session
            case .busy:
                logger.error("Intent readiness rejected: session command is still running")
                throw PhoneIntentError.busy
            case .failed:
                logCaptureState(session, stage: "readiness")
                throw PhoneIntentError.cameraBusy
            case .wait: try await Task.sleep(for: .milliseconds(50))
            }
        }
        throw PhoneIntentError.openExperiment
    }

    private func logCaptureState(_ session: ExperimentSessionFeature.State, stage: String) {
        let capture = session.capture
        let camera = "visible=\(capture.isCameraViewVisible) "
            + "ready=\(capture.previewConnector != nil) switching=\(capture.isCameraSwitching)"
        let photo = "scheduled=\(capture.isPhotoCaptureScheduled) "
            + "capturing=\(capture.isCapturingPhoto) data=\(capture.capturedPhotoData != nil) "
            + "request=\(capture.photo.requestedRecordID != nil) "
            + "confirmation=\(capture.photo.requiresExternalConfirmation)"
        let video = "idle=\(capture.videoPhase == .idle) "
            + "request=\(capture.video.requestedRecordID != nil) "
            + "confirmation=\(capture.video.requiresExternalConfirmation)"
        logger.error("Capture rejected: stage=\(stage, privacy: .public)")
        logger.error("Camera \(camera, privacy: .public); photo \(photo, privacy: .public)")
        let voiceHidden = session.voice.phase == .hidden
        logger.error("Video \(video, privacy: .public); voiceHidden=\(voiceHidden)")
    }

    private func requestWatchVoice(_ experimentID: UUID) async throws -> String {
        guard !FileManager.default.fileExists(atPath: pendingURL.path) else {
            logger.error("Voice request blocked: previous result is unresolved")
            pendingResolutionRequested = true
            throw PhoneIntentError.unknown
        }
        guard WCSession.isSupported() else {
            logger.error("Voice request rejected: WatchConnectivity is unsupported")
            throw PhoneIntentError.watchUnavailable
        }
        let activated = WCSession.default.activationState == .activated
        let reachable = WCSession.default.isReachable
        guard activated, reachable else {
            logger.error("Voice request rejected: activated=\(activated) reachable=\(reachable)")
            throw PhoneIntentError.watchUnavailable
        }
        let request = WatchRemoteIntentRequest(
            requestID: UUID(), experimentID: experimentID, expiresAt: .now.addingTimeInterval(3)
        )
        let data = try JSONEncoder().encode(request)
        do {
            try FileManager.default.createDirectory(
                at: pendingURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try data.write(
                to: pendingURL,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
        } catch { throw PhoneIntentError.storage }
        let responseKey = WatchRemoteIntentResponse.messageKey
        let response = try await VoiceReply.wait(for: request.requestID) { finish in
            WCSession.default.sendMessage(
                [WatchRemoteIntentRequest.messageKey: data]
            ) { @Sendable reply in
                let data = reply[responseKey] as? Data
                Task { @MainActor in finish(data) }
            } errorHandler: { @Sendable _ in
                Task { @MainActor in finish(nil) }
            }
        }
        do { try FileManager.default.removeItem(at: pendingURL) } catch {
            throw PhoneIntentError.storage
        }
        guard response.accepted else { throw PhoneIntentError.rejected(response.message) }
        return "Watch에 음성 기록 요청을 접수했어요. 녹음과 저장 결과를 확인해주세요."
    }
}

private enum PhoneIntentError: LocalizedError {
    case busy, openExperiment, cameraBusy, contextChanged, watchUnavailable, unknown, storage
    case rejected(String)

    var errorDescription: String? {
        switch self {
        case .busy: "다른 단축어 요청을 처리 중이에요."
        case .openExperiment: "iPhone에서 진행 중인 실험을 먼저 열어주세요."
        case .cameraBusy: "iPhone 카메라를 준비하거나 진행 중인 기록을 확인해주세요."
        case .contextChanged: "실험 화면이 바뀌었어요. 현재 상태를 확인해주세요."
        case .watchUnavailable: "Watch 앱을 열고 iPhone 연결을 확인해주세요."
        case .unknown: "요청 결과를 확인하지 못했어요. 앱에서 확인한 뒤 다시 실행해주세요."
        case .storage: "요청 상태를 보관하거나 정리하지 못했어요. 앱에서 확인해주세요."
        case let .rejected(message): message
        }
    }
}

@MainActor
private final class VoiceReply {
    private var continuation: CheckedContinuation<WatchRemoteIntentResponse, Error>?
    private var timeout: Task<Void, Never>?
    private var cancelled = false

    static func wait(
        for requestID: UUID,
        send: (@escaping @MainActor (Data?) -> Void) -> Void
    ) async throws -> WatchRemoteIntentResponse {
        let gate = VoiceReply()
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
