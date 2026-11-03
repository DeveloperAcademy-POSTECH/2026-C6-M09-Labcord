import AVKit
import ImageIO
import LabcordDesignSystem
import LabcordiOS
import LabcordShared
import SwiftUI

struct ExperimentHistoryRecordView: View {
    let record: ExperimentResultDetail.Record
    @Binding var activeMediaID: UUID?
    @State private var showsVideo = false

    private var mediaURL: URL? {
        guard let path = record.filePath, !path.isEmpty else { return nil }
        let url = URL.applicationSupportDirectory.appending(path: path).standardizedFileURL
        let root = URL.applicationSupportDirectory.standardizedFileURL.path + "/"
        guard url.path.hasPrefix(root), FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return url
    }

    private var timelineType: TimelineItemType {
        switch record.type {
        case .audio: .voice
        case .photo: .photo
        case .video: .video
        case .timer: .timer
        }
    }

    var body: some View {
        TimelineItem(
            record.transcript.flatMap { $0.isEmpty ? nil : $0 } ?? "음성 기록",
            timestamp: ExperimentHistoryDateFormatter.time(record.recordedAt),
            memo: record.note,
            showMemo: !record.note.isEmpty,
            type: timelineType
        ) {
            recordContent
        }
        .accessibilityIdentifier("history-record-\(record.id)")
        .sheet(isPresented: $showsVideo) {
            if let mediaURL { HistoryVideoPlayer(url: mediaURL) }
        }
    }

    @ViewBuilder
    private var recordContent: some View {
        switch record.type {
        case .audio:
            if let mediaURL {
                HistoryAudioPlayer(
                    url: mediaURL, recordID: record.id, activeMediaID: $activeMediaID
                )
            } else {
                missingMedia
            }
        case .photo, .video:
            if let mediaURL {
                if record.type == .video {
                    Button {
                        activeMediaID = record.id
                        showsVideo = true
                    } label: {
                        HistoryMediaThumbnail(url: mediaURL, isVideo: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("영상 기록 재생")
                } else {
                    HistoryMediaThumbnail(url: mediaURL, isVideo: false)
                }
            } else {
                missingMedia
            }
        case .timer:
            timerContent
        }
    }

    private var missingMedia: some View {
        Text("저장된 미디어 파일을 찾을 수 없어요.")
            .typography(Typography.subheadline)
            .foregroundStyle(Color("General/Label/Secondary",
                                   bundle: LabcordDesignSystemResources.bundle))
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }

    private var timerContent: some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing4) {
            if let seconds = record.timerDurationSeconds {
                Text("설정 시간 \(Duration.seconds(seconds).formatted(.labcordDuration))")
            }
            Text(record.timerEndedAt == nil ? "타이머 실행" : "타이머 종료")
            if let endedAt = record.timerEndedAt {
                Text("종료 \(ExperimentHistoryDateFormatter.time(endedAt))")
            }
            if !record.timerPauses.isEmpty {
                Text("일시정지 \(record.timerPauses.count)회")
                ForEach(record.timerPauses, id: \.id) { pause in
                    Text("일시정지 \(ExperimentHistoryDateFormatter.time(pause.pausedAt))")
                    if let resumedAt = pause.resumedAt {
                        Text("재개 \(ExperimentHistoryDateFormatter.time(resumedAt))")
                    }
                }
            }
        }
        .typography(Typography.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HistoryMediaThumbnail: View {
    let url: URL
    let isVideo: Bool
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            Color("General/Fill/Primary", bundle: LabcordDesignSystemResources.bundle)
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Text(failed ? "미리보기를 불러오지 못했어요." : "미리보기 불러오는 중")
                    .typography(Typography.subheadline)
            }
            if isVideo {
                Image(labcordIcon: .play)
                    .padding(LayoutTokens.spacing12)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: LayoutTokens.radiusSm))
        .task(id: url) {
            image = nil
            failed = false
            if isVideo {
                let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 1_200, height: 1_200)
                if let result = try? await generator.image(at: .zero), !Task.isCancelled {
                    image = UIImage(cgImage: result.image)
                }
            } else if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 1_200
                      ] as CFDictionary) {
                image = UIImage(cgImage: thumbnail)
            }
            failed = image == nil
        }
    }
}

private struct HistoryVideoPlayer: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var player: AVPlayer?

    var body: some View {
        NavigationStack {
            VideoPlayer(player: player)
                .navigationTitle("영상 기록")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("닫기") { dismiss() }
                    }
                }
        }
        .onAppear { player = AVPlayer(url: url) }
        .onDisappear {
            player?.pause()
            player = nil
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { player?.pause() }
        }
    }
}
