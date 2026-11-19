import ComposableArchitecture
import Foundation
import LabcordShared
import LabcordWatchOS
import Observation
import OSLog
import WatchKit

private let logger = Logger(
    subsystem: "com.researchers.Researchers.watchkitapp", category: "WatchShortcut"
)

typealias WatchRecordingShortcut = WatchRemoteIntentRequest.Kind

/// Watch 단축어와 iPhone 단축어 요청을 현재 화면에 전달합니다.
/// Watch에서 시작한 단축어는 앱을 여는 동안만 화면 등록을 기다립니다.
@MainActor
@Observable
final class WatchRecordingShortcutCenter {
    /// 요청을 처리했으면 `true`를 반환합니다. `experimentID`가 `nil`이면 실험을 가리지 않습니다.
    typealias Handler = @MainActor (WatchRecordingShortcut, UUID?) -> Bool

    static let shared = WatchRecordingShortcutCenter()

    enum Receiver { case experiment, voiceRecording }

    private struct Entry {
        let experimentID: UUID
        let handle: Handler
    }

    private struct Restoration {
        let id: UUID
        let experiment: WatchExperimentSummary
        let proof: ScreenProof
        let departure: UUID
        let deadline: ContinuousClock.Instant
    }

    private var restoration: Restoration?
    var restorationID: UUID? { restoration?.id }

    func currentRestoration() -> (WatchExperimentSummary, WatchScreenSnapshot)? {
        @Dependency(\.watchConnectivitySession) var connectivity
        guard let restoration, lastDeparture == restoration.departure,
              ContinuousClock.now < restoration.deadline,
              let screen = connectivity.experiments.latestScreen,
              restoration.proof.matches(screen, id: restoration.experiment.id) else { return nil }
        return (restoration.experiment, screen)
    }

    private var handlers: [Receiver: Entry] = [:]
    private var visibleExperimentID: UUID?
    private var lastDeparture = UUID()
    private var remoteAttempts: [UUID: (expiresAt: Date, task: Task<Bool, Never>)] = [:]

    private var receiver: Entry? { handlers[.voiceRecording] ?? handlers[.experiment] }

    private init() {}

    func enterExperiment(_ id: UUID) {
        if let visibleExperimentID, visibleExperimentID != id { lastDeparture = UUID() }
        visibleExperimentID = id
    }

    func register(_ receiver: Receiver, in experimentID: UUID, handle: @escaping Handler) {
        if receiver == .experiment, handlers[.voiceRecording]?.experimentID != experimentID {
            handlers[.voiceRecording] = nil
        }
        handlers[receiver] = Entry(experimentID: experimentID, handle: handle)
    }

    func dismissVoice(in experimentID: UUID) {
        if handlers[.voiceRecording]?.experimentID == experimentID {
            handlers[.voiceRecording] = nil
        }
    }

    func leaveExperiment(_ experimentID: UUID) {
        if visibleExperimentID == experimentID || receiver?.experimentID == experimentID {
            lastDeparture = UUID()
        }
        handlers = handlers.filter { $0.value.experimentID != experimentID }
        if visibleExperimentID == experimentID { visibleExperimentID = nil }
    }

    func performLocal(_ shortcut: WatchRecordingShortcut) async throws {
        let attempt = Attempt(kind: shortcut, origin: "local", departure: lastDeparture)
        let deadline = attempt.started.advanced(by: .seconds(WatchGesturePracticeRequest.lifetime))
        trace(attempt, "entry")
        do {
            try Task.checkCancellation()
            @Dependency(\.watchConnectivitySession) var connectivity
            if let id = visibleExperimentID ?? receiver?.experimentID {
                trace(attempt, "route=local")
                let latest = connectivity.experiments.latestScreen
                let waiting = receiver?.experimentID != id && latest?.recordingExperimentID == id
                try await deliver(
                    attempt, to: id,
                    proof: waiting ? latest?.gestureSession.map(ScreenProof.session) : nil,
                    until: deadline
                )
            } else {
                trace(attempt, "route=askingPhone")
                let request = WatchGesturePracticeRequest(kind: shortcut, requestID: attempt.id)
                let route = try await connectivity.resolveGestureRoute(request, until: deadline)
                switch route {
                case .practice:
                    trace(attempt, "route=practice handled=true")
                case let .experiment(screen, age, summary):
                    try await restore(
                        attempt, screen: screen, age: age, summary: summary,
                        deadline: deadline
                    )
                case nil:
                    throw ContinuousClock.now < deadline ? Failure.noRoute : Failure.expired
                }
            }
        } catch {
            trace(attempt, "rejected=\(error)")
            throw error
        }
    }

    private func restore(
        _ attempt: Attempt, screen: WatchScreenSnapshot, age: TimeInterval,
        summary: WatchExperimentSummary?, deadline: ContinuousClock.Instant
    ) async throws {
        @Dependency(\.watchConnectivitySession) var connectivity
        trace(attempt, "route=restoringExperiment")
        let lifetime = WatchGesturePracticeRequest.lifetime
        guard let id = screen.recordingExperimentID, let epoch = screen.epoch,
              age.isFinite, Duration.seconds(min(max(age, 0), lifetime))
                >= attempt.started.duration(to: .now) else { throw Failure.newSession }
        let proof = screen.gestureSession.map(ScreenProof.session)
            ?? .legacy(epoch, revision: screen.revision)
        guard proof.matches(screen, id: id) else { throw Failure.newSession }
        connectivity.experiments.receiveScreen(screen)
        if let summary, summary.id == id, summary.status == .running {
            restoration = Restoration(
                id: attempt.id, experiment: summary, proof: proof,
                departure: attempt.departure, deadline: deadline
            )
        }
        defer { if restoration?.id == attempt.id { restoration = nil } }
        try await deliver(
            attempt, to: id, proof: proof, until: deadline
        )
    }

    private enum ScreenProof {
        case session(WatchGestureSession)
        case legacy(WatchStateEpoch, revision: UInt64)

        func matches(_ screen: WatchScreenSnapshot?, id: UUID) -> Bool {
            switch self {
            case let .session(value): return value.matches(screen, experimentID: id)
            case let .legacy(epoch, revision):
                return screen?.recordingExperimentID == id && screen?.gestureSession == nil
                    && screen?.epoch == epoch && screen?.revision == revision && revision > 0
            }
        }
    }

    private func deliver(
        _ attempt: Attempt, to id: UUID, proof: ScreenProof? = nil,
        until deadline: ContinuousClock.Instant
    ) async throws {
        @Dependency(\.watchConnectivitySession) var connectivity
        var firstWait: String?
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            guard lastDeparture == attempt.departure,
                  visibleExperimentID == nil || visibleExperimentID == id else {
                throw Failure.leftExperiment
            }
            let screen = connectivity.experiments.latestScreen
            let matches = proof?.matches(screen, id: id) ?? true
            if matches, let receiver, receiver.experimentID == id {
                // ExperimentView.onAppear가 path.onChange보다 먼저 올 수 있습니다.
                if let firstWait { trace(attempt, "wait=\(firstWait) resolved") }
                let handled = receiver.handle(attempt.kind, id)
                trace(attempt, "delivery handled=\(handled)")
                guard handled else { throw Failure.receiverDeclined }
                return
            }
            if firstWait == nil { firstWait = waitStatus(id: id, screen: screen, proof: proof) }
            let next = ContinuousClock.now.advanced(by: .milliseconds(50))
            try await Task.sleep(until: min(next, deadline), tolerance: .zero, clock: .continuous)
        }
        let end = waitStatus(id: id, screen: connectivity.experiments.latestScreen, proof: proof)
        trace(attempt, "wait=\(firstWait ?? "deadline") final=\(end)")
        throw Failure.expired
    }

    private func waitStatus(
        id: UUID, screen: WatchScreenSnapshot?, proof: ScreenProof?
    ) -> String {
        let interval = screen?.gestureSession?.start.revision.description ?? "nil"
        let revision = screen?.revision.description ?? "nil"
        return "visible=\(visibleExperimentID == id),receiver=\(receiver?.experimentID == id),"
            + "cacheID=\(screen?.recordingExperimentID == id),rev=\(revision),"
            + "interval=\(interval),proof=\(proof?.matches(screen, id: id) ?? true)"
    }

    func receive(_ request: WatchRemoteIntentRequest) async -> WatchRemoteIntentResponse {
        let attempt = Attempt(
            id: request.requestID, kind: request.kind, origin: "phone", departure: lastDeparture
        )
        trace(attempt, "entry")
        remoteAttempts = remoteAttempts.filter { $0.value.expiresAt > .now }
        let handled: Bool
        if let prior = remoteAttempts[request.requestID] {
            trace(attempt, "duplicate")
            handled = await prior.task.value
        } else if request.expiresAt > .now {
            let remaining = min(request.expiresAt.timeIntervalSinceNow,
                                WatchGesturePracticeRequest.lifetime)
            let deadline = ContinuousClock.now.advanced(by: .seconds(remaining))
            let task = Task { @MainActor in
                do {
                    // 이전 iPhone 요청은 식별 가능한 현재 화면에서만 즉시 처리합니다.
                    if request.gestureSession == nil,
                       receiver?.experimentID != request.experimentID {
                        throw Failure.noRoute
                    }
                    trace(attempt, "route=remoteExperiment")
                    try await deliver(
                        attempt, to: request.experimentID,
                        proof: request.gestureSession.map(ScreenProof.session),
                        until: deadline
                    )
                    return true
                } catch {
                    trace(attempt, "rejected=\(error)")
                    return false
                }
            }
            remoteAttempts[request.requestID] = (request.expiresAt, task)
            handled = await task.value
        } else {
            trace(attempt, "rejected=expired")
            handled = false
        }
        WatchConnectivityDiagnostics.event(
            handled ? "intent.handled" : "intent.notHandled", id: request.requestID.uuidString
        )
        return WatchRemoteIntentResponse(
            requestID: request.requestID, accepted: handled,
            message: handled ? "Watch에서 기록을 실행했어요." : "Watch 실험 화면에서 기록을 실행할 수 없어요."
        )
    }

    private struct Attempt {
        var id = UUID()
        let kind: WatchRecordingShortcut
        let origin: String
        let departure: UUID
        let started = ContinuousClock.now
    }

    private enum Failure: String, LocalizedError {
        case noRoute, newSession, leftExperiment, receiverDeclined, expired

        var errorDescription: String? {
            "Watch에서 진행 중인 실험이나 iPhone의 Apple Watch 제스처 연습 화면을 열어 주세요."
        }
    }

}

private extension WatchRecordingShortcutCenter {
    private func trace(_ attempt: Attempt, _ event: String) {
        let status = "app=\(Self.applicationState) handlers=\(handlers.count)"
        let line = "intent \(attempt.kind.rawValue) id=\(attempt.origin) \(status) \(event)"
            + " attempt=\(attempt.id.uuidString)"
        logger.notice("\(line, privacy: .public)")
        #if DEBUG
        Self.appendDebugLog(line)
        #endif
    }

    #if DEBUG
    static func appendDebugLog(_ event: String) {
        let directory = URL.cachesDirectory.appending(path: "LabcordDiagnostics")
        let file = directory.appending(path: "watch-shortcuts.log")
        let timestamp = Date.now.ISO8601Format()
        let line = Data("\(timestamp) \(event)\n".utf8)
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true
            )
            let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize
            if let size, size < 65_536 {
                let handle = try FileHandle(forWritingTo: file)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
            } else {
                try line.write(to: file, options: .atomic)
            }
        } catch {
            logger.error("Could not write shortcut diagnostics")
        }
    }
    #endif

    static var applicationState: String {
        switch WKApplication.shared().applicationState {
        case .active: "active"
        case .inactive: "inactive"
        case .background: "background"
        @unknown default: "unknown"
        }
    }
}
