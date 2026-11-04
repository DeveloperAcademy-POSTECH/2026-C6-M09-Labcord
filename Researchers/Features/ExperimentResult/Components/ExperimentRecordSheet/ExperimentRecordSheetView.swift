import LabcordDesignSystem
import LabcordiOS
import LabcordShared
import SwiftUI

struct ExperimentRecordSheetView: View {
    let entry: ExperimentResultDetail.TimelineEntry
    let onDismiss: () -> Void

    var body: some View {
        if let presentation = ExperimentRecordSheetPresentation(entry: entry) {
            let record = presentation.record
            RecordBottomSheet(
                type: presentation.type,
                setDuration: presentation.timer?.setDuration ?? "",
                timerState: presentation.timer?.state ?? .start,
                timerElapsedTime: presentation.timer?.elapsedTime ?? "",
                timerCumulativeTime: presentation.timer?.cumulativeTime ?? "",
                timerPauseCount: presentation.timer?.pauseCount ?? "",
                voiceContent: voiceContent(for: presentation),
                mediaContent: mediaContent(for: presentation),
                transcriptContent: AnyView(readOnlyText(record.transcript ?? "")),
                noteContent: AnyView(readOnlyText(record.note)),
                transcriptHelp: "",
                onDismiss: onDismiss,
                showsActions: false
            )
        }
    }

    private func voiceContent(for presentation: ExperimentRecordSheetPresentation) -> AnyView? {
        guard presentation.record.type == .audio else { return nil }
        guard let url = presentation.mediaURL else {
            return AnyView(Text("음성 파일을 불러올 수 없습니다."))
        }
        return AnyView(RecordedAudioTimelineView(url: url))
    }

    private func mediaContent(for presentation: ExperimentRecordSheetPresentation) -> AnyView? {
        switch presentation.record.type {
        case .photo:
            guard let url = presentation.mediaURL,
                  let image = UIImage(contentsOfFile: url.path) else {
                return AnyView(Text("사진 파일을 불러올 수 없습니다."))
            }
            return AnyView(
                GeometryReader { geometry in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                }
            )
        case .video:
            guard let url = presentation.mediaURL else {
                return AnyView(Text("영상 파일을 불러올 수 없습니다."))
            }
            return AnyView(RecordedVideoTimelineView(url: url))
        case .audio, .timer:
            return nil
        }
    }

    private func readOnlyText(_ value: String) -> some View {
        Text(value.isEmpty ? "내용이 없습니다." : value)
            .typography(Typography.subheadline)
            .foregroundStyle(Color("General/Label/Primary"))
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .padding(LayoutTokens.spacing12)
    }
}
