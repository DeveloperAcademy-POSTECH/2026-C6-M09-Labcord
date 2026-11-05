import AVFAudio
import ComposableArchitecture
import Foundation
import LabcordShared
import LabcordWatchOS
import OSLog
#if os(watchOS)
import WatchKit
#endif

/// 화면과 App Shortcut은 이 Store 하나를 사용한다. Intent마다 Store를 만들지 않는다.
@MainActor
final class WatchIntentRuntime {
    static let shared = WatchIntentRuntime(
        store: Store(initialState: WatchExperimentFeature.State()) {
            WatchExperimentFeature(recordingBridge: .live)
        },
        isActive: {
            #if os(watchOS)
            WKApplication.shared().applicationState == .active
            #else
            false
            #endif
        },
        microphoneAllowed: { AVAudioApplication.shared.recordPermission == .granted }
    )

    let store: StoreOf<WatchExperimentFeature>
    private let isActive: @MainActor () -> Bool
    private let microphoneAllowed: @MainActor () -> Bool
    private var isPerforming = false
    private let logger = Logger(subsystem: "com.researchers.Researchers.watchkitapp",
                                category: "WatchIntentRuntime")

    init(
        store: StoreOf<WatchExperimentFeature>,
        isActive: @escaping @MainActor () -> Bool,
        microphoneAllowed: @escaping @MainActor () -> Bool
    ) {
        self.store = store
        self.isActive = isActive
        self.microphoneAllowed = microphoneAllowed
    }

    func perform(_ kind: WatchRecordPresentation.Kind) async throws -> String {
        try await perform(kind, remote: nil)
    }

    func performRemoteVoice(experimentID: UUID, expiresAt: Date) async throws -> String {
        let remote = RemoteVoice(experimentID: experimentID, expiresAt: expiresAt)
        try validateRemote(remote)
        return try await perform(.voice, remote: remote)
    }

    private struct RemoteVoice {
        let experimentID: UUID
        let expiresAt: Date
    }

    private func validateRemote(_ remote: RemoteVoice?) throws {
        guard let remote else { return }
        guard Date.now < remote.expiresAt else {
            throw WatchIntentRuntimeError.requestRejected("음성 요청이 만료됐어요. 다시 시도해주세요.")
        }
        guard store.selectedID == remote.experimentID,
              store.snapshot?.experiment.status == .running,
              store.screen == .experiment || store.screen == .timers else {
            throw WatchIntentRuntimeError.contextChanged
        }
    }

    private func perform(
        _ kind: WatchRecordPresentation.Kind, remote: RemoteVoice?
    ) async throws -> String {
        logger.info("Intent invoked: \(String(describing: kind), privacy: .public)")
        guard !isPerforming else { throw WatchIntentRuntimeError.busy }
        isPerforming = true
        defer { isPerforming = false }
        let startedInPractice = store.screen == .gestures
        let selectionBeforeActivation = store.selectedID
        let canRestoreSelection = selectionBeforeActivation == nil
            && (!isActive() || !store.isVisible || store.streamID == nil)
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        do {
            try await waitForRoot(until: deadline, remote: remote)
            try validateRemote(remote)
            logger.info("Intent foreground ready")
            let selectedID = canRestoreSelection ? store.selectedID : selectionBeforeActivation
            try validateLease(practice: startedInPractice, selectedID: selectedID)
            if startedInPractice {
                _ = try WatchIntentRouting.action(for: kind, state: store.withState { $0 })
                store.send(.practiceRecord(kind))
                guard let feedback = store.practice.feedback else {
                    throw WatchIntentRuntimeError.notReady
                }
                return feedback
            }
            if kind == .voice, let stop = WatchIntentRouting.localVoiceStop(
                state: store.withState { $0 }
            ) {
                return try await execute(stop, kind: kind, remote: remote)
            }
            if let pending = store.pending,
               !WatchRequestPolicy.isReadOnly(pending.command.operation) {
                throw WatchIntentRuntimeError.busy
            }
            if kind == .voice, store.selectedID != nil, !store.isReachable {
                let action = try WatchIntentRouting.action(
                    for: kind, state: store.withState { $0 }
                )
                if !microphoneAllowed() { throw WatchIntentRuntimeError.permissionRequired }
                return try await execute(action, kind: kind, remote: remote)
            }
            try await refresh(until: deadline, remote: remote)
            try validateRemote(remote)
            try validateLease(practice: false, selectedID: selectedID)
            if store.selectedID == nil { try await selectRunningExperiment(until: deadline) }
            try validateRemote(remote)
            let action = try WatchIntentRouting.action(for: kind, state: store.withState { $0 })
            return try await execute(action, kind: kind, remote: remote)
        } catch is CancellationError {
            throw WatchIntentRuntimeError.interrupted
        }
    }

    private func execute(
        _ action: WatchExperimentFeature.Action, kind: WatchRecordPresentation.Kind,
        remote: RemoteVoice?
    ) async throws -> String {
        guard isActive(), store.isVisible else { throw WatchIntentRuntimeError.appNotActive }
        try validateRemote(remote)
        if kind == .voice, case .recordTapped = action, !microphoneAllowed() {
            throw WatchIntentRuntimeError.permissionRequired
        }
        let previousIDs = Set(store.recording.records.keys)
        let experimentID = store.selectedID
        if let remote, case .recordTapped(.voice) = action {
            store.send(.remoteVoiceRequested(remote.experimentID, remote.expiresAt))
        } else {
            store.send(action)
        }
        logger.info("Intent dispatched recording action")
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while true {
            try Task.checkCancellation()
            guard isActive(), store.isVisible, store.selectedID == experimentID else {
                throw WatchIntentRuntimeError.contextChanged
            }
            if try verifyAccepted(
                action, previousIDs: previousIDs, experimentID: experimentID,
                remoteVoice: remote != nil
            ) { break }
            if let remote, Date.now >= remote.expiresAt {
                throw WatchIntentRuntimeError.requestRejected(
                    "음성 요청의 실행 여부를 확인하지 못했어요. 앱에서 상태를 확인해주세요."
                )
            }
            if kind == .photo, ContinuousClock.now >= deadline {
                throw WatchIntentRuntimeError.photoResultPending
            }
            try await pause(until: deadline)
        }
        logger.info("Intent recording request accepted; capture and save are not confirmed")
        return "기록 요청을 접수했어요."
    }

    private func waitForRoot(
        until deadline: ContinuousClock.Instant, remote: RemoteVoice?
    ) async throws {
        while !isActive() || !store.isVisible || store.streamID == nil {
            try validateRemote(remote)
            try await pause(until: deadline)
        }
    }

    private func validateLease(practice: Bool, selectedID: UUID?) throws {
        guard (store.screen == .gestures) == practice, store.selectedID == selectedID else {
            throw WatchIntentRuntimeError.contextChanged
        }
    }

    private func refresh(
        until deadline: ContinuousClock.Instant, remote: RemoteVoice?
    ) async throws {
        guard isActive(), store.isVisible, store.isReachable,
              store.hasRestoredPending, !store.pendingRecoveryFailed else {
            throw WatchIntentRuntimeError.notReady
        }
        while store.pending != nil {
            try validateRemote(remote)
            guard let pending = store.pending,
                  WatchRequestPolicy.isReadOnly(pending.command.operation) else {
                throw WatchIntentRuntimeError.busy
            }
            try await pause(until: deadline)
        }
        try validateRemote(remote)
        store.send(.refresh)
        guard let requestID = store.pending?.command.requestID else {
            throw WatchIntentRuntimeError.notReady
        }
        try await waitForRead(requestID, until: deadline, remote: remote)
    }

    private func selectRunningExperiment(until deadline: ContinuousClock.Instant) async throws {
        guard store.selectedID == nil else { throw WatchIntentRuntimeError.contextChanged }
        let candidates = store.experiments.filter { $0.status == .running }
        guard candidates.count == 1,
              !store.recording.records.values.contains(where: { !$0.isSettled }) else {
            throw WatchIntentRuntimeError.selectExperiment
        }
        store.send(.selected(candidates[0].id))
        guard store.selectedID == candidates[0].id,
              let requestID = store.pending?.command.requestID else {
            throw WatchIntentRuntimeError.notReady
        }
        try await waitForRead(requestID, until: deadline, remote: nil)
        guard store.selectedID == candidates[0].id else {
            throw WatchIntentRuntimeError.contextChanged
        }
    }

    private func waitForRead(
        _ id: UUID, until deadline: ContinuousClock.Instant, remote: RemoteVoice?
    ) async throws {
        while store.lastReadRequestID != id {
            try validateRemote(remote)
            guard isActive(), store.isVisible, store.streamID != nil else {
                throw WatchIntentRuntimeError.contextChanged
            }
            guard store.pending?.command.requestID == id else {
                throw WatchIntentRuntimeError.notReady
            }
            try await pause(until: deadline)
        }
    }

    private func pause(until deadline: ContinuousClock.Instant) async throws {
        guard ContinuousClock.now < deadline else {
            throw isActive() ? WatchIntentRuntimeError.notReady : .appNotActive
        }
        try await Task.sleep(for: .milliseconds(50))
    }

    private func verifyAccepted(
        _ action: WatchExperimentFeature.Action, previousIDs: Set<UUID>, experimentID: UUID?,
        remoteVoice: Bool
    ) throws -> Bool {
        let record: WatchRecordPresentation?
        switch action {
        case let .recordTapped(kind):
            record = store.recording.records.values.first {
                !previousIDs.contains($0.id) && $0.kind == kind && $0.experimentID == experimentID
            }
        case let .recording(.stop(id)):
            record = store.recording.records[id].flatMap { $0.phase == .capturing ? nil : $0 }
        default:
            throw WatchIntentRuntimeError.notReady
        }
        guard let record else { return false }
        if record.phase == .failed {
            throw WatchIntentRuntimeError.requestRejected(record.detail ?? "기록 요청을 처리하지 못했어요.")
        }
        if record.phase == .cancelled { throw WatchIntentRuntimeError.interrupted }
        if case .recordTapped(.photo) = action {
            return record.startedAt != nil || [.review, .saving, .saved].contains(record.phase)
        }
        if remoteVoice, case .recordTapped(.voice) = action {
            return record.phase == .capturing
        }
        return true
    }
}
