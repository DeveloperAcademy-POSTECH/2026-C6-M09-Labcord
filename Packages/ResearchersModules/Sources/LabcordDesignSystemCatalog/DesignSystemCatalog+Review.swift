import LabcordDesignSystem
import SwiftUI

struct DesignSystemReviewPage: View {
    let item: CatalogItem

    @State private var presentedRecord: CatalogRecordPresentation?
    @State private var recordType = RecordType.photo
    @State private var recordContentState = RecordContentState.filled
    @State private var recordMemo = ""
    @State private var recordTranscript = ""
    @State private var savedRecordMemo = "실험 결과를 기록했어요."
    @State private var savedRecordTranscript = "샘플 B, 반응 시작 5분 후 연한 노란색으로 변했고 침전은 없음"
    @State private var timerRecordExample = CatalogTimerRecordExample.short
    @State private var sheetTimerExample = CatalogTimerRecordExample.short
    @State private var timerRecordState = TimerRecordState.paused
    @State private var timerIdentity = TimerIdentity.identity02
    @State private var deletionScenario = CatalogTimerDeletionScenario.duringRun
    @State private var timelineType = TimelineItemType.voice
    @State private var timelineState = TimelineItemState.default
    @State private var showsTimelineMemo = true
    @State private var showsVoiceDuration = true

    var body: some View {
        DesignSystemCatalogPage(title: item.title, context: item.context) {
            switch item {
            case .timelineItem: timelineItemCard
            case .experimentStatusTimelineItem: experimentStatusTimelineItemCard
            case .timerRecord: timerRecordCard
            case .voicePlayer: voicePlayerCard
            case .recordBottomSheet: recordBottomSheetCard
            case .photoViewer: mediaViewerCard(isVideo: false)
            case .videoPlayer: mediaViewerCard(isVideo: true)
            default: EmptyView()
            }
        }
        .fullScreenCover(item: $presentedRecord, onDismiss: discardRecordEdits) { record in
            DesignSystemCatalogSheet(context: item.context) {
                CatalogRecordSheetSample(
                    type: record.type,
                    identity: timerIdentity,
                    timerExample: record.timerExample,
                    memo: $recordMemo,
                    transcript: $recordTranscript,
                    initialTranscript: record.transcriptAtOpen,
                    onDismiss: cancelRecord,
                    onSave: saveRecord,
                    onDelete: deleteRecord
                )
            }
        }
    }

    private var timelineItemCard: some View {
        DesignSystemCatalogCard("Timeline Item", description: "4종류 × 기본·선택 상태와 메모 표시") {
            Picker("종류", selection: $timelineType) {
                catalogPickerOptions(TimelineItemType.allCases)
            }
            .accessibilityIdentifier("catalog.review.timeline.type")
            Picker("상태", selection: $timelineState) {
                catalogPickerOptions(TimelineItemState.allCases)
            }
            .accessibilityIdentifier("catalog.review.timeline.state")
            Toggle("메모 표시", isOn: $showsTimelineMemo)
                .accessibilityIdentifier("catalog.review.timeline.memo")

            TimelineItem(
                "샘플 B, 반응 시작 5분 후 연한 노란색으로 변했고 침전은 없음",
                timestamp: "10:18:02",
                memo: "색이 연한 노란색으로 변했으나 침전은 없음",
                showMemo: showsTimelineMemo,
                type: timelineType,
                state: timelineState
            ) {
                timelineMedia
            }
            .accessibilityIdentifier("catalog.review.timeline.preview")
        }
    }

    @ViewBuilder
    private var timelineMedia: some View {
        switch timelineType {
        case .voice:
            CatalogVoiceSample()
        case .photo:
            Button { openMediaRecord(.photo, contentState: .filled) } label: {
                CatalogSampleMedia()
            }
            .buttonStyle(LabcordPlainButtonStyle())
            .accessibilityLabel(Text("사진 기록 열기"))
            .accessibilityIdentifier("catalog.motion.timelinePhoto")
        case .video:
            Button {
                openMediaRecord(.video, contentState: .filled)
            } label: {
                CatalogSampleMedia(isVideo: true)
                    .overlay {
                        Image(labcordIcon: .play)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                            .foregroundStyle(Color("General/Label/Inverse", bundle: catalogBundle))
                            .padding(14)
                            .background(
                                Color("General/Brand/Primary", bundle: catalogBundle),
                                in: Circle()
                            )
                    }
            }
            .buttonStyle(LabcordPlainButtonStyle())
            .accessibilityLabel(Text("영상 기록 열기"))
        case .timer:
            TimerRecord(
                setDuration: .seconds(30), elapsedTime: .seconds(4),
                cumulativeTime: .seconds(4), pauseCount: 1,
                state: .end, identity: timerIdentity
            )
        }
    }

    private var experimentStatusTimelineItemCard: some View {
        DesignSystemCatalogCard(
            "Experiment Status Timeline Item", description: "실험 상태가 바뀐 시점의 기록"
        ) {
            TimelineExperimentState("실험 시작", timestamp: "10:17:24")
        }
    }

    private var timerRecordCard: some View {
        DesignSystemCatalogCard("Timer Record", description: "5개 기록 상태와 5개 식별색 미리보기") {
            Picker("기록 예시", selection: $timerRecordExample) {
                catalogPickerOptions(CatalogTimerRecordExample.allCases, capitalized: false)
            }
            .accessibilityIdentifier("catalog.review.timerRecord.example")
            .onChange(of: timerRecordExample) { _, example in
                if example != .short { timerRecordState = .paused }
            }
            Picker("상태", selection: $timerRecordState) {
                catalogPickerOptions(TimerRecordState.allCases)
            }
            .accessibilityIdentifier("catalog.review.timerRecord.state")
            Picker("Timer Identity", selection: $timerIdentity) {
                catalogPickerOptions(TimerIdentity.allCases, capitalized: false)
            }
            .accessibilityIdentifier("catalog.review.timerRecord.identity")
            Button("타이머 삭제", role: .destructive) { timerRecordState = .deleted }
                .buttonStyle(.labcord(.quaternary, size: .small))
                .disabled(timerRecordState == .deleted)
            if timerRecordState == .deleted {
                Picker("삭제 전 상황", selection: $deletionScenario) {
                    catalogPickerOptions(CatalogTimerDeletionScenario.allCases, capitalized: false)
                }
                .accessibilityIdentifier("catalog.review.timerRecord.deletionScenario")
            }

            if timerRecordState != .deleted || deletionScenario == .duringRun {
                TimerRecord(
                    setDuration: timerRecordExample.setDuration,
                    elapsedTime: timerRecordExample.elapsedTime,
                    cumulativeTime: timerRecordExample.cumulativeTime,
                    pauseCount: "(1)",
                    state: timerRecordState,
                    identity: timerIdentity
                )
                .accessibilityIdentifier("catalog.review.timerRecord.preview")
            } else {
                Text("실행 후 종료 전에 삭제한 타이머만 삭제 기록을 표시합니다.")
                    .typography(Typography.footnote)
                    .foregroundStyle(Color("General/Label/Secondary", bundle: catalogBundle))
                    .accessibilityIdentifier("catalog.review.timerRecord.deletionGuard")
            }

        }
    }

    private var voicePlayerCard: some View {
        DesignSystemCatalogCard("Voice Player", description: "음성 재생과 위치 탐색") {
            Toggle("재생 시간 표시", isOn: $showsVoiceDuration)
                .accessibilityIdentifier("catalog.review.voice.duration")
            CatalogVoiceSample(showDuration: showsVoiceDuration)
        }
    }

    private var recordBottomSheetCard: some View {
        DesignSystemCatalogCard(
            "Record Bottom Sheet", description: "4종류 × 메모 Empty·Filled 상태의 실제 모달"
        ) {
            Picker("종류", selection: $recordType) {
                catalogPickerOptions(RecordType.allCases)
            }
            .accessibilityIdentifier("catalog.review.recordSheet.type")
            Picker("메모 상태", selection: $recordContentState) {
                catalogPickerOptions(RecordContentState.allCases)
            }
            .accessibilityIdentifier("catalog.review.recordSheet.content")
            if recordType == .timer {
                Picker("기록 예시", selection: $sheetTimerExample) {
                    catalogPickerOptions(CatalogTimerRecordExample.allCases, capitalized: false)
                }
                .accessibilityIdentifier("catalog.review.recordSheet.timerExample")
            }
            if recordType == .video {
                Text("영상은 로컬 재생 데모를 자동으로 반복합니다.")
                    .typography(Typography.footnote)
                    .foregroundStyle(Color("General/Label/Secondary", bundle: catalogBundle))
            }
            Button("기록 바텀 시트 열기", action: openRecord)
                .buttonStyle(.labcord(.primary, size: .medium))
                .accessibilityIdentifier("catalog.review.recordSheet.open")
        }
    }

}

private extension DesignSystemReviewPage {
    func openRecord() {
        if recordContentState == .filled && savedRecordMemo.isEmpty {
            recordMemo = "실험 결과를 기록했어요."
            recordTranscript = "샘플 B, 반응 시작 5분 후 연한 노란색으로 변했고 침전은 없음"
        } else {
            recordMemo = recordContentState == .filled ? savedRecordMemo : ""
            recordTranscript = savedRecordTranscript
        }
        presentedRecord = CatalogRecordPresentation(
            type: recordType, timerExample: sheetTimerExample,
            transcriptAtOpen: recordTranscript
        )
    }

    func saveRecord() {
        savedRecordMemo = recordMemo
        savedRecordTranscript = recordTranscript
        recordContentState = recordMemo.isEmpty ? .empty : .filled
        presentedRecord = nil
    }

    func cancelRecord() {
        presentedRecord = nil
    }

    func deleteRecord() {
        savedRecordMemo = ""
        savedRecordTranscript = ""
        recordContentState = .empty
        presentedRecord = nil
    }

    func discardRecordEdits() {
        recordMemo = savedRecordMemo
        recordTranscript = savedRecordTranscript
    }

    func mediaViewerCard(isVideo: Bool) -> some View {
        DesignSystemCatalogCard(
            isVideo ? "Video Player" : "Photo Viewer",
            description: isVideo
                ? "영상을 눌러 자동·반복 재생" : "사진을 눌러 사진과 메모 확인"
        ) {
            Picker("메모 상태", selection: $recordContentState) {
                catalogPickerOptions(RecordContentState.allCases)
            }
            .accessibilityIdentifier(
                isVideo
                    ? "catalog.review.videoPlayer.content" : "catalog.review.photoViewer.content"
            )
            Button { openMediaRecord(isVideo ? .video : .photo) } label: {
                CatalogSampleMedia(isVideo: isVideo)
                    .overlay {
                        if isVideo {
                            Image(labcordIcon: .play)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 24, height: 24)
                                .foregroundStyle(
                                    Color("General/Label/Inverse", bundle: catalogBundle)
                                )
                                .padding(14)
                                .background(
                                    Color("General/Brand/Primary", bundle: catalogBundle),
                                    in: Circle()
                                )
                        }
                    }
            }
            .buttonStyle(LabcordPlainButtonStyle())
            .accessibilityLabel(Text(isVideo ? "비디오 플레이어 열기" : "사진 뷰어 열기"))
            .accessibilityIdentifier(
                isVideo ? "catalog.review.videoPlayer.open" : "catalog.review.photoViewer.open"
            )
        }
    }

    func openMediaRecord(
        _ type: RecordType,
        contentState: RecordContentState? = nil
    ) {
        recordType = type
        if let contentState { recordContentState = contentState }
        openRecord()
    }
}

private struct CatalogRecordPresentation: Identifiable {
    let type: RecordType
    let timerExample: CatalogTimerRecordExample
    let transcriptAtOpen: String

    var id: String { type.rawValue }
}

private enum CatalogTimerDeletionScenario: String, CaseIterable {
    case beforeStart = "실행 전"
    case duringRun = "실행 후·종료 전"
    case afterFinish = "종료 후"
}

#Preview("기록 검토 · 타임라인") {
    _ = FontRegistration.register()
    return NavigationStack {
        DesignSystemReviewPage(item: .timelineItem)
    }
}
