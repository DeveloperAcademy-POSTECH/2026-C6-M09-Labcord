import AVFoundation
import LabcordDesignSystem
import LabcordiOS
import LabcordShared
import SwiftUI

struct ExperimentRecordSheetView: View {
    let entry: ExperimentResultDetail.TimelineEntry
    @Binding var note: String
    @Binding var transcript: String
    let canSave: Bool
    let onDismiss: () -> Void
    let onSave: () -> Void
    let onDelete: () -> Void
    let onScrollTargetChange: (RecordBottomSheetScrollTarget?) -> Void
    let isVideoFullScreen: Bool
    let onOpenVideoFullScreen: (AVPlayer) -> Void

    var body: some View {
        if let presentation = ExperimentRecordSheetPresentation(entry: entry) {
            RecordBottomSheet(
                type: presentation.type,
                contentState: canSave ? .filled : .empty,
                setDuration: presentation.timer?.setDuration ?? "",
                timerState: presentation.timer?.state ?? .start,
                timerElapsedTime: presentation.timer?.elapsedTime ?? "",
                timerCumulativeTime: presentation.timer?.cumulativeTime ?? "",
                timerPauseCount: presentation.timer?.pauseCount ?? "",
                voiceContent: voiceContent(for: presentation),
                transcript: $transcript,
                note: $note,
                mediaContent: mediaContent(for: presentation),
                onDismiss: onDismiss,
                onScrollTargetChange: onScrollTargetChange,
                onSave: onSave,
                onDelete: onDelete,
                showsHeader: false
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
            return AnyView(
                ExperimentRecordVideoPlayerView(
                    url: url,
                    isFullScreen: isVideoFullScreen,
                    onOpenFullScreen: onOpenVideoFullScreen
                )
                .id(url)
            )
        case .audio, .timer:
            return nil
        }
    }

}
