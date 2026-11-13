import ComposableArchitecture
import Foundation
import LabcordiOS
import LabcordShared

extension ExperimentResultFeature.State {
    var selectedRecord: ExperimentResultDetail.Record? {
        guard let selectedEntry else { return nil }
        switch selectedEntry.kind {
        case let .record(record), let .timer(record, _): return record
        default: return nil
        }
    }

    var normalizedNote: String {
        draftNote.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasUnsavedRecordChanges: Bool {
        guard let selectedEntry else { return false }
        return draftNote != selectedEntry.note
            || (selectedRecord?.type == .audio
                && draftTranscript != (selectedRecord?.transcript ?? ""))
    }

    var canSaveRecord: Bool {
        guard !isRecordSaving, selectedRecord != nil else { return false }
        let transcript = editedTranscript
        guard transcript?.isEmpty != true else { return false }
        let noteChanged = normalizedNote
            != (selectedEntry?.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return (noteChanged || transcript != nil)
            && draftNote.count <= 300
    }

    var canRefreshExternalRecords: Bool {
        !isRecordSaving && selectedEntry == nil && titleEditOverlay == nil
            && !isInitialLoadPending
    }
}

extension ExperimentResultFeature {
    var externalRecordReducer: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .externalRecordsChanged:
                state.needsExternalReload = true
            case let .externalDetailLoaded(token, detail):
                guard token == state.externalReloadID else { return .none }
                state.externalReloadID = nil
                guard state.canRefreshExternalRecords else {
                    state.needsExternalReload = true
                    return .none
                }
                if let detail, detail.id == state.experimentID {
                    state.recordTimeline = RecordTimelineFeature.State(detail: detail)
                }
                if !state.needsExternalReload { return .none }
            case .recordMutationSucceeded, .titleEditOverlay(.delegate(.saved)):
                if state.externalReloadID != nil {
                    state.externalReloadID = nil
                    state.needsExternalReload = true
                }
            default:
                break
            }
            guard state.needsExternalReload, state.externalReloadID == nil,
                  state.canRefreshExternalRecords else { return .none }
            let token = UUID()
            let experimentID = state.experimentID
            state.externalReloadID = token
            state.needsExternalReload = false
            return .run { send in
                let detail = try? await experimentClient.loadResultDetail(experimentID)
                await send(.externalDetailLoaded(token, detail))
            }
        }
    }
}
