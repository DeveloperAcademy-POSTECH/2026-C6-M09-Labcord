import ComposableArchitecture
import Foundation
import LabcordShared

@Reducer
struct WatchRecordFeature {
    enum Decision: Equatable, Sendable {
        case save
        case cancel
    }

    @ObservableState
    struct State: Equatable {
        var records: [UUID: WatchRecordPresentation] = [:]
        var focusedID: UUID?
        var autoSaveSeconds: [UUID: Int] = [:]
        var decisions: [UUID: Decision] = [:]
        var failedDecisions: Set<UUID> = []
        var isIntegrated = false
        var notice: String?

        var focused: WatchRecordPresentation? { focusedID.flatMap { records[$0] } }
        func hasUnsettledRecords(in experimentID: UUID?) -> Bool {
            guard let experimentID else { return false }
            return records.values.contains { $0.experimentID == experimentID && !$0.isSettled }
        }
    }

    enum Action: Equatable {
        case begin(WatchRecordPresentation.Kind, UUID)
        case stop(UUID)
        case update(WatchRecordPresentation)
        case commandProcessed(UUID, WatchExperimentCommand.Operation)
        case commandFailed(UUID, String)
        case captureRejected(UUID, String)
        case preparationCancelled(UUID)
        case recapture(UUID)
        case autoSaveTick(UUID, UInt64)
        case confirm(UUID)
        case cancel(UUID)
        case retry(UUID)
        case open(UUID)
        case close
        case integrationAvailable(Bool)
        case interrupted
        case recoveryFailed
        case delegate(Delegate)
    }

    enum Delegate: Equatable {
        case command(WatchExperimentCommand.Operation, recordID: UUID, experimentID: UUID)
        case local(WatchRecordingUIBridge.Input)
    }

    nonisolated enum CancelID: Hashable, Sendable {
        case autoSave(UUID)
    }

    @Dependency(\.uuid) var uuid
    @Dependency(\.continuousClock) var clock

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case let .begin(kind, experimentID):
                return begin(kind, experimentID: experimentID, state: &state)
            case let .stop(id):
                guard var record = state.records[id], record.phase == .capturing else {
                    return .none
                }
                record.phase = .stopping
                state.records[id] = record
                if record.kind == .voice {
                    return .send(.delegate(.local(.stopVoice(
                        experimentID: record.experimentID, recordID: id
                    ))))
                }
                return .send(.delegate(.command(
                    .stopVideo, recordID: id, experimentID: record.experimentID
                )))
            case let .update(record):
                return update(record, state: &state)
            case let .commandProcessed(id, operation):
                guard var record = state.records[id], !record.isSettled else { return .none }
                if operation == .startVideo {
                    // 경과 시간의 기준은 backend의 capturing update에서 받는다.
                    record.detail = "영상 시작 처리를 확인했어요. 최신 상태를 받는 중이에요."
                } else {
                    record.detail = "iPhone 처리를 확인했어요. 최종 저장 확인을 기다리고 있어요."
                }
                state.records[id] = record
                return .none
            case let .captureRejected(id, message):
                guard var record = state.records[id], record.phase == .starting,
                      !record.originalRetained else { return .none }
                record.phase = .failed
                record.captureRejectedBeforeStart = true
                record.detail = message
                record.canAutoSave = false
                state.records[id] = record
                return .none
            case let .recapture(id):
                guard state.isIntegrated, let record = state.records[id],
                      record.canRecapture else {
                    return .none
                }
                return .send(.begin(record.kind, record.experimentID))
            case let .preparationCancelled(id):
                guard let record = state.records[id], record.kind == .photo,
                      record.phase == .starting
                        || (record.phase == .saving && state.decisions[id] == .cancel),
                      !record.originalRetained else { return .none }
                state.records[id]?.phase = .cancelled
                state.records[id]?.detail = "촬영 요청을 보내기 전에 취소했어요."
                state.decisions[id] = nil
                state.failedDecisions.remove(id)
                return .none
            case let .commandFailed(id, message):
                guard var record = state.records[id], !record.isSettled else { return .none }
                record.phase = .failed
                if state.decisions[id] != nil { state.failedDecisions.insert(id) }
                record.detail = message
                record.canAutoSave = false
                state.records[id] = record
                state.autoSaveSeconds[id] = nil
                return .cancel(id: CancelID.autoSave(id))
            case let .confirm(id):
                return confirm(id, state: &state)
            case let .cancel(id):
                guard state.isIntegrated, let record = state.records[id],
                      record.phase == .review
                        || (record.phase == .starting && record.kind == .photo)
                        || (record.phase == .failed
                            && (record.originalRetained || record.kind != .voice)),
                      state.decisions[id] == nil || record.phase == .failed else { return .none }
                state.decisions[id] = .cancel
                state.failedDecisions.remove(id)
                state.autoSaveSeconds[id] = nil
                state.records[id]?.canAutoSave = false
                state.records[id]?.phase = .saving
                return .merge(
                    .cancel(id: CancelID.autoSave(id)),
                    .send(.delegate(.command(
                        .cancelRecord, recordID: id, experimentID: record.experimentID
                    )))
                )
            case let .autoSaveTick(id, revision):
                return autoSaveTick(id, revision: revision, state: &state)
            case let .retry(id):
                return retry(id, state: &state)
            case let .open(id):
                state.focusedID = id
                return .none
            case .close:
                // 닫아도 녹음·원본·저장 대기를 폐기하지 않는다.
                state.focusedID = nil
                return .none
            case let .integrationAvailable(available):
                state.isIntegrated = available
                if available { state.notice = nil }
                return .none
            case .recoveryFailed:
                state.notice = "기록 상태를 다시 받지 못했어요. 원본을 유지하고 다시 연결해주세요."
                state.isIntegrated = false
                return cancelAutoSave(state: &state)
            case .interrupted:
                return cancelAutoSave(state: &state)
            case .delegate:
                return .none
            }
        }
    }

}

private extension WatchRecordFeature {
    func begin(
        _ kind: WatchRecordPresentation.Kind, experimentID: UUID, state: inout State
    ) -> Effect<Action> {
        guard state.isIntegrated else {
            state.notice = "기록 기능 연결이 필요해요. iPhone에서 기록해주세요."
            return .none
        }
        if let record = state.records.values.first(where: {
            $0.experimentID == experimentID && $0.kind == kind && !$0.isSettled
        }) {
            state.focusedID = record.id
            return .none
        }
        let record = WatchRecordPresentation(id: uuid(), experimentID: experimentID, kind: kind)
        state.records[record.id] = record
        state.focusedID = record.id
        if kind == .voice {
            return .send(.delegate(.local(.startVoice(
                experimentID: experimentID, recordID: record.id
            ))))
        }
        return .send(.delegate(.command(
            kind == .photo ? .takePhoto : .startVideo,
            recordID: record.id, experimentID: experimentID
        )))
    }

    func update(
        _ record: WatchRecordPresentation, state: inout State
    ) -> Effect<Action> {
        if let previous = state.records[record.id] {
            guard previous.experimentID == record.experimentID, previous.kind == record.kind,
                  !previous.isSettled, record.revision > previous.revision else { return .none }
        }
        var update = record
        if record.isSettled {
            state.decisions[record.id] = nil
            state.failedDecisions.remove(record.id)
        } else if state.decisions[record.id] != nil {
            update.canAutoSave = false
            if state.failedDecisions.contains(record.id) {
                update.phase = .failed
                update.detail = state.records[record.id]?.detail
            } else if update.phase == .review { update.phase = .saving }
        }
        state.records[record.id] = update
        if update.phase == .review, update.canAutoSave, state.isIntegrated {
            state.autoSaveSeconds[record.id] = 3
            return autoSave(id: record.id, revision: record.revision)
        }
        state.autoSaveSeconds[record.id] = nil
        return .cancel(id: CancelID.autoSave(record.id))
    }

    func retry(_ id: UUID, state: inout State) -> Effect<Action> {
        guard state.isIntegrated, let record = state.records[id],
              record.phase == .failed, record.originalRetained else { return .none }
        state.failedDecisions.remove(id)
        if record.kind == .voice, state.decisions[id] != .cancel {
            // Explicit retry restarts receipt/review recovery, never a new recording.
            state.decisions[id] = nil
            return .send(.delegate(.local(.retry(
                experimentID: record.experimentID, recordID: id
            ))))
        }
        let decision = state.decisions[id] ?? .save
        state.decisions[id] = decision
        state.records[id]?.phase = .saving
        return .send(.delegate(.command(
            decision == .cancel ? .cancelRecord : .confirmRecord,
            recordID: id, experimentID: record.experimentID
        )))
    }

    func confirm(_ id: UUID, state: inout State) -> Effect<Action> {
        guard state.isIntegrated, let record = state.records[id],
              record.phase == .review, state.decisions[id] == nil else { return .none }
        state.decisions[id] = .save
        state.autoSaveSeconds[id] = nil
        state.records[id]?.phase = .saving
        state.records[id]?.canAutoSave = false
        return .merge(
            .cancel(id: CancelID.autoSave(id)),
            .send(.delegate(.command(
                .confirmRecord, recordID: id, experimentID: record.experimentID
            )))
        )
    }

    func autoSaveTick(
        _ id: UUID, revision: UInt64, state: inout State
    ) -> Effect<Action> {
        guard state.isIntegrated, let record = state.records[id], record.revision == revision,
              record.phase == .review, let seconds = state.autoSaveSeconds[id] else {
            return .none
        }
        guard seconds > 1 else { return confirm(id, state: &state) }
        state.autoSaveSeconds[id] = seconds - 1
        return autoSave(id: id, revision: revision)
    }

    func cancelAutoSave(state: inout State) -> Effect<Action> {
        let effects: [Effect<Action>] = state.autoSaveSeconds.keys.map {
            .cancel(id: CancelID.autoSave($0))
        }
        state.autoSaveSeconds = [:]
        return .merge(effects)
    }

    func autoSave(id: UUID, revision: UInt64) -> Effect<Action> {
        .run { [clock] send in
            try await clock.sleep(for: .seconds(1))
            await send(.autoSaveTick(id, revision))
        }
        .cancellable(id: CancelID.autoSave(id), cancelInFlight: true)
    }
}
