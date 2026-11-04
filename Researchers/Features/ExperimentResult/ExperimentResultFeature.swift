//
//  ExperimentResultFeature.swift
//  Researchers
//
//  Created by 정홍섭 on 10/29/26.
//

import ComposableArchitecture
import Foundation
import LabcordiOS
import LabcordShared

@Reducer
struct ExperimentResultFeature {
    enum RecordFilter: CaseIterable, Hashable {
        case all
        case photo
        case audio
        case video
        case timer
    }

    enum RecordSort: CaseIterable, Hashable {
        case oldest
        case newest
    }

    @ObservableState
    struct State: Equatable {
        let experimentID: UUID
        let isOpenedFromHome: Bool
        var recordTimeline: RecordTimelineFeature.State?
        var loadMessage: String?
        var selectedType: RecordFilter = .all
        var selectedSort: RecordSort = .oldest
        var selectedEntry: ExperimentResultDetail.TimelineEntry?
        var draftNote = ""
        var draftTranscript = ""
        var isRecordSaving = false
        var isRecordDeleteConfirmationPresented = false
        var recordSaveMessage: String?
        var titleEditOverlay: TitleEditOverlayFeature.State?

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

        var editedTranscript: String? {
            guard let selectedRecord, selectedRecord.type == .audio else { return nil }
            let transcript = draftTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            let original = (selectedRecord.transcript ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return transcript == original ? nil : transcript
        }

        var canSaveRecord: Bool {
            guard !isRecordSaving, selectedRecord != nil else { return false }
            let noteChanged = normalizedNote
                != (selectedEntry?.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return (noteChanged || editedTranscript != nil)
                && draftNote.count <= 300
                && (editedTranscript == nil || draftTranscript.count <= 300)
        }

        mutating func clearRecordDraft() {
            selectedEntry = nil
            draftNote = ""
            draftTranscript = ""
        }

        var displayedEntries: [ExperimentResultDetail.TimelineEntry] {
            guard let entries = recordTimeline?.entries else { return [] }

            if selectedType == .all {
                return selectedSort == .oldest ? entries : Array(entries.reversed())
            }

            let matchesType: (ExperimentResultDetail.TimelineEntry) -> Bool = { entry in
                switch (selectedType, entry.kind) {
                case let (.photo, .record(record)):
                    record.type == .photo
                case let (.audio, .record(record)):
                    record.type == .audio
                case let (.video, .record(record)):
                    record.type == .video
                case (.timer, .timer):
                    true
                default:
                    false
                }
            }

            return selectedSort == .oldest
                ? entries.filter(matchesType)
                : entries.reversed().filter(matchesType)
        }

        init(experimentID: UUID, isOpenedFromHome: Bool = false) {
            self.experimentID = experimentID
            self.isOpenedFromHome = isOpenedFromHome
        }
    }

    enum Action: Equatable {
        case loadResultDetail
        case resultDetailLoaded(ExperimentResultDetail?)
        case resultDetailLoadFailed
        case recordFilterSelected(RecordFilter)
        case recordSortSelected(RecordSort)
        case timelineEntrySelected(ExperimentResultDetail.TimelineEntry)
        case timelineSheetDismissed
        case recordNoteChanged(String)
        case recordTranscriptChanged(String)
        case recordSaveTapped
        case recordDeleteTapped
        case recordDeleteConfirmed
        case recordDeleteCancelled
        case recordMutationSucceeded(ExperimentResultDetail, UUID)
        case recordMutationFailed
        case recordSaveMessageDismissed
        case recordTimeline(RecordTimelineFeature.Action)
        case editTapped
        case titleEditOverlay(TitleEditOverlayFeature.Action)
        case homeTapped
    }

    @Dependency(\.experimentClient) var experimentClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .loadResultDetail:
                state.recordTimeline = nil
                state.loadMessage = nil
                state.clearRecordDraft()
                state.isRecordDeleteConfirmationPresented = false
                let experimentID = state.experimentID
                return .run { send in
                    async let minimumDisplay = Task.sleep(for: .seconds(1))
                    await Task.yield()
                    guard !Task.isCancelled else { return }

                    let detail: ExperimentResultDetail?
                    let loadFailed: Bool
                    do {
                        detail = try await experimentClient.loadResultDetail(experimentID)
                        loadFailed = false
                    } catch {
                        detail = nil
                        loadFailed = true
                    }

                    do {
                        try await minimumDisplay
                        try Task.checkCancellation()
                    } catch {
                        return
                    }

                    if loadFailed {
                        await send(.resultDetailLoadFailed)
                    } else {
                        await send(.resultDetailLoaded(detail))
                    }
                }

            case let .resultDetailLoaded(detail):
                state.recordTimeline = detail.map { RecordTimelineFeature.State(detail: $0) }
                state.loadMessage = detail == nil ? "실험을 찾을 수 없습니다." : nil
                return .none

            case .resultDetailLoadFailed:
                state.loadMessage = "실험을 불러오지 못했습니다."
                return .none

            case let .recordFilterSelected(filter):
                state.selectedType = filter
                return .none

            case let .recordSortSelected(sort):
                state.selectedSort = sort
                return .none

            case let .timelineEntrySelected(entry):
                guard !state.isRecordSaving else { return .none }
                switch entry.kind {
                case let .record(record), let .timer(record, _):
                    state.selectedEntry = entry
                    state.draftNote = entry.note
                    state.draftTranscript = record.type == .audio ? record.transcript ?? "" : ""
                case .status, .started, .ended, .paused, .resumed:
                    break
                }
                return .none

            case .timelineSheetDismissed:
                state.clearRecordDraft()
                state.isRecordDeleteConfirmationPresented = false
                return .none

            case let .recordNoteChanged(note):
                guard !state.isRecordSaving else { return .none }
                state.draftNote = String(note.prefix(300))
                return .none

            case let .recordTranscriptChanged(transcript):
                guard !state.isRecordSaving, state.selectedRecord?.type == .audio else {
                    return .none
                }
                state.draftTranscript = String(transcript.prefix(300))
                return .none

            case .recordSaveTapped:
                guard state.canSaveRecord,
                      let record = state.selectedRecord else { return .none }
                state.isRecordSaving = true
                let experimentID = state.experimentID
                let note = state.normalizedNote
                let transcript = state.editedTranscript
                let timerEventID = record.type == .timer ? state.selectedEntry?.id : nil
                return .run { send in
                    do {
                        let detail = try await experimentClient.updateRecordContent(
                            experimentID, record.id, note, transcript, timerEventID
                        )
                        await send(.recordMutationSucceeded(detail, record.id))
                    } catch {
                        await send(.recordMutationFailed)
                    }
                }

            case .recordDeleteTapped:
                guard !state.isRecordSaving, state.selectedRecord != nil else { return .none }
                state.isRecordDeleteConfirmationPresented = true
                return .none

            case .recordDeleteConfirmed:
                guard !state.isRecordSaving,
                      let recordID = state.selectedRecord?.id else { return .none }
                state.isRecordDeleteConfirmationPresented = false
                state.isRecordSaving = true
                let experimentID = state.experimentID
                return .run { send in
                    do {
                        let detail = try await experimentClient.deleteRecord(
                            experimentID, recordID
                        )
                        await send(.recordMutationSucceeded(detail, recordID))
                    } catch {
                        await send(.recordMutationFailed)
                    }
                }

            case .recordDeleteCancelled:
                state.isRecordDeleteConfirmationPresented = false
                return .none

            case let .recordMutationSucceeded(detail, recordID):
                guard detail.id == state.experimentID else { return .none }
                state.isRecordSaving = false
                if state.selectedRecord?.id == recordID {
                    state.clearRecordDraft()
                }
                return .send(.recordTimeline(.detailUpdated(detail)))

            case .recordMutationFailed:
                state.isRecordSaving = false
                state.recordSaveMessage = "기록을 변경하지 못했습니다. 다시 시도해 주세요."
                return .none

            case .recordSaveMessageDismissed:
                state.recordSaveMessage = nil
                return .none

            case .editTapped:
                guard let title = state.recordTimeline?.detail.title else { return .none }
                state.titleEditOverlay = TitleEditOverlayFeature.State(
                    experimentID: state.experimentID,
                    originalTitle: title
                )
                return .none

            case let .titleEditOverlay(.delegate(.saved(detail))):
                guard detail.id == state.experimentID,
                      state.recordTimeline != nil else { return .none }
                state.titleEditOverlay = nil
                return .send(.recordTimeline(.detailUpdated(detail)))

            case .titleEditOverlay(.delegate(.dismiss)):
                state.titleEditOverlay = nil
                return .none

            case .titleEditOverlay:
                return .none

            case .recordTimeline:
                return .none

            case .homeTapped:
                return .none
            }
        }
        .ifLet(\.titleEditOverlay, action: \.titleEditOverlay) {
            TitleEditOverlayFeature()
        }
        .ifLet(\.recordTimeline, action: \.recordTimeline) {
            RecordTimelineFeature()
        }
    }
}
