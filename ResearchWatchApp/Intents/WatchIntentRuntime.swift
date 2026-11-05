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
        logger.info("Intent invoked: \(String(describing: kind), privacy: .public)")
        guard !isPerforming else { throw WatchIntentRuntimeError.busy }
        isPerforming = true
        defer { isPerforming = false }
        let startedInPractice = store.screen == .gestures
        let selectedID = store.selectedID
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        do {
            try await waitForRoot(until: deadline)
            logger.info("Intent foreground ready")
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
                return try await execute(stop, kind: kind)
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
                return try await execute(action, kind: kind)
            }
            try await refresh(until: deadline)
            try validateLease(practice: false, selectedID: selectedID)
            if store.selectedID == nil { try await selectRunningExperiment(until: deadline) }
            let action = try WatchIntentRouting.action(for: kind, state: store.withState { $0 })
            return try await execute(action, kind: kind)
        } catch is CancellationError {
            throw WatchIntentRuntimeError.interrupted
        }
    }

    private func execute(
        _ action: WatchExperimentFeature.Action, kind: WatchRecordPresentation.Kind
    ) async throws -> String {
        guard isActive(), store.isVisible else { throw WatchIntentRuntimeError.appNotActive }
        if kind == .voice, case .recordTapped = action, !microphoneAllowed() {
            throw WatchIntentRuntimeError.permissionRequired
        }
        let previousIDs = Set(store.recording.records.keys)
        let experimentID = store.selectedID
        store.send(action)
        logger.info("Intent dispatched recording action")
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while true {
            try Task.checkCancellation()
            guard isActive(), store.isVisible, store.selectedID == experimentID else {
                throw WatchIntentRuntimeError.contextChanged
            }
            if try verifyAccepted(
                action, previousIDs: previousIDs, experimentID: experimentID
            ) { break }
            try await pause(until: deadline)
        }
        logger.info("Intent recording request accepted; capture and save are not confirmed")
        return "기록 요청을 접수했어요. 앱에서 처리·저장 결과를 확인해주세요."
    }

    private func waitForRoot(until deadline: ContinuousClock.Instant) async throws {
        while !isActive() || !store.isVisible || store.streamID == nil {
            try await pause(until: deadline)
        }
    }

    private func validateLease(practice: Bool, selectedID: UUID?) throws {
        guard (store.screen == .gestures) == practice, store.selectedID == selectedID else {
            throw WatchIntentRuntimeError.contextChanged
        }
    }

    private func refresh(until deadline: ContinuousClock.Instant) async throws {
        guard isActive(), store.isVisible, store.isReachable,
              store.hasRestoredPending, !store.pendingRecoveryFailed else {
            throw WatchIntentRuntimeError.notReady
        }
        while store.pending != nil {
            guard let pending = store.pending,
                  WatchRequestPolicy.isReadOnly(pending.command.operation) else {
                throw WatchIntentRuntimeError.busy
            }
            try await pause(until: deadline)
        }
        store.send(.refresh)
        guard let requestID = store.pending?.command.requestID else {
            throw WatchIntentRuntimeError.notReady
        }
        try await waitForRead(requestID, until: deadline)
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
        try await waitForRead(requestID, until: deadline)
        guard store.selectedID == candidates[0].id else {
            throw WatchIntentRuntimeError.contextChanged
        }
    }

    private func waitForRead(_ id: UUID, until deadline: ContinuousClock.Instant) async throws {
        while store.lastReadRequestID != id {
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
        _ action: WatchExperimentFeature.Action, previousIDs: Set<UUID>, experimentID: UUID?
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
        return true
    }
}
