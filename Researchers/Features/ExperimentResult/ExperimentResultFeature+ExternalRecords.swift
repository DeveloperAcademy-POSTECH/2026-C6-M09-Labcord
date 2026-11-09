import Foundation
import LabcordiOS

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

    var canSaveRecord: Bool {
        guard !isRecordSaving, selectedRecord != nil else { return false }
        let noteChanged = normalizedNote
            != (selectedEntry?.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return (noteChanged || editedTranscript != nil)
            && draftNote.count <= 300
    }

    var canRefreshExternalRecords: Bool {
        !isRecordSaving && selectedEntry == nil && titleEditOverlay == nil && !isResuming
            && !isInitialLoadPending
    }
}
