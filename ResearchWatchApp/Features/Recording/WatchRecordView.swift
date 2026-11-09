import ComposableArchitecture
import LabcordShared
import SwiftUI

struct WatchRecordView: View {
    let store: StoreOf<WatchRecordFeature>
    let record: WatchRecordPresentation

    var body: some View {
        VStack(spacing: 8) {
            if record.phase == .saved {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.blue)
                    .accessibilityHidden(true)
            }
            if record.phase == .failed {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 30, weight: .medium))
                    .accessibilityHidden(true)
            }
            if record.phase != .review, record.phase != .capturing,
               record.phase != .saved, record.phase != .failed {
                Text(kindTitle)
                    .font(.headline)
            }
            if record.phase != .capturing || record.kind != .voice {
                if record.phase != .review || record.kind != .voice || record.transcript.isEmpty {
                    Text(phaseTitle)
                        .font(record.phase == .review || record.phase == .failed
                              ? .headline : .body)
                        .multilineTextAlignment(.center)
                }
            }
            if record.kind == .voice, record.phase == .capturing {
                Image(systemName: "waveform")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(.blue)
                    .accessibilityHidden(true)
            }
            if record.kind == .photo, record.phase == .starting, record.startedAt != nil {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    if let seconds = record.photoCountdownRemaining(at: context.date),
                       seconds > 0 {
                        Text("촬영까지 \(seconds)초").monospacedDigit()
                    } else { Text("촬영 결과 확인 중").font(.caption) }
                }
            }
            if let startedAt = record.startedAt, record.phase == .capturing {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let elapsed = max(0, Int(context.date.timeIntervalSince(startedAt)))
                    HStack(spacing: 4) {
                        if record.kind == .video {
                            Circle().fill(.red).frame(width: 8, height: 8)
                        }
                        Text(WatchPresentationRules.formatDuration(elapsed))
                            .monospacedDigit()
                    }
                }
            } else if record.elapsedSeconds > 0 {
                Text(WatchPresentationRules.formatDuration(record.elapsedSeconds))
                    .monospacedDigit()
            }
            transcript
            if record.originalRetained, record.phase != .review {
                Label("확보한 원본 보관 중", systemImage: "internaldrive")
                    .font(.caption2)
            }
            if let detail = record.detail {
                Text(detail)
                    .font(.caption)
            }
            controls
            if record.phase == .failed {
                Button("닫기", role: .cancel) { store.send(.close) }
            }
        }
    }

    @ViewBuilder
    private var transcript: some View {
        if !record.transcript.isEmpty {
            Text(record.transcript)
                .font(.caption)
            if !record.isFinalTranscript {
                Text("실시간 전사 · 변경될 수 있어요")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        if record.hasTranscriptConflict {
            Text("수정한 전사와 재전사 결과가 달라요. iPhone에서 비교해주세요. 수정본은 자동으로 덮어쓰지 않아요.")
                .font(.caption)
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch record.phase {
        case .starting:
            if record.kind == .photo {
                Text("iPhone에서 촬영을 준비하고 있어요.").font(.caption)
                Button("촬영 대기 취소", role: .cancel) { store.send(.cancel(record.id)) }
            } else { ProgressView() }
        case .capturing:
            if record.kind == .voice {
                Button("완료") { store.send(.stop(record.id)) }
                    .padding(.top, 8)
            } else {
                Button("녹화 중지", systemImage: "stop.fill") { store.send(.stop(record.id)) }
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("녹화 중지")
            }
        case .review:
            if let seconds = store.autoSaveSeconds[record.id] {
                Text("\(seconds)초 후 자동 저장을 요청해요.")
                    .font(.caption)
            }
            HStack {
                Button("취소", systemImage: "arrow.counterclockwise", role: .destructive) {
                    store.send(.cancel(record.id))
                }
                .labelStyle(.iconOnly)
                .accessibilityLabel("기록 취소")
                .accessibilityHint("다시 기록하려면 현재 기록을 취소한 뒤 새로 시작하세요.")
                Spacer()
                Button("저장", systemImage: "checkmark") { store.send(.confirm(record.id)) }
                    .labelStyle(.iconOnly)
                    .tint(.blue)
                    .accessibilityLabel("기록 저장")
            }
        case .failed:
            if record.canRecapture {
                Button(
                    record.kind == .voice ? "다시 녹음" : "다시 촬영",
                    systemImage: record.kind == .voice ? "mic" : "camera"
                ) { store.send(.recapture(record.id)) }
            } else if record.kind == .voice, record.requiresSavedVerification,
                      !record.originalRetained {
                Button("저장 상태 다시 확인", systemImage: "arrow.clockwise") {
                    store.send(.retry(record.id))
                }
            } else if record.originalRetained {
                Button(record.kind == .voice ? "원본으로 재시도" : "저장 다시 시도",
                       systemImage: "arrow.clockwise") {
                    store.send(.retry(record.id))
                }
                Button("기록 취소", role: .destructive) { store.send(.cancel(record.id)) }
            } else {
                Text("원본과 처리 결과를 먼저 확인해주세요.").font(.caption)
                Button("상태 확인") { store.send(.delegate(.local(.reconcile))) }
                if record.kind != .voice {
                    Button("미확정 기록 취소", role: .destructive) { store.send(.cancel(record.id)) }
                }
            }
        case .saved:
            EmptyView()
        case .cancelled:
            Text("취소 결과를 확인했어요.")
                .font(.caption)
        default:
            ProgressView()
        }
    }

    private var kindTitle: String {
        switch record.kind {
        case .voice: "음성 기록"
        case .photo: "사진 기록"
        case .video: "영상 기록"
        }
    }

    private var phaseTitle: String {
        switch record.phase {
        case .starting: record.kind == .photo ? "촬영 중" : "기록 시작 확인 중"
        case .capturing: record.kind == .voice ? "녹음 중" : "녹화 중"
        case .stopping: "기록 중지·보관 중"
        case .transferring:
            record.originalRetained ? "보관 원본 전송·누락 복구 중" : "기록 전송·처리 상태 확인 중"
        case .transcribing: "전사 대기·처리 중"
        case .review:
            switch record.kind {
            case .voice: "음성 기록 확인"
            case .photo: "해당 장면을\n저장할까요?"
            case .video: "해당 영상을\n저장할까요?"
            }
        case .saving: "iPhone 최종 저장·취소 확인 중"
        case .saved: "저장 완료"
        case .failed: "기록 처리 실패"
        case .cancelled: "기록 취소됨"
        }
    }
}

struct WatchRecordControls: View {
    let store: StoreOf<WatchExperimentFeature>

    var body: some View {
        VStack(spacing: 8) {
            if !store.recording.isIntegrated {
                Text("음성·촬영·저장 상태 연결이 필요해요. iPhone에서 기록해주세요.")
                    .font(.caption)
                Button("기록 상태 다시 연결") { store.send(.recordReconnect) }
            }
            HStack(spacing: 8) {
                Button("음성 기록", systemImage: "mic.fill") {
                    store.send(.recordTapped(.voice))
                }
                .disabled(!canRecord)
                Button("사진 촬영", systemImage: "camera.fill") {
                    store.send(.recordTapped(.photo))
                }
                .disabled(!canRecord || !store.isReachable)
            }
            .labelStyle(.iconOnly)
            HStack {
                Button("영상 녹화", systemImage: "video.fill") {
                    store.send(.recordTapped(.video))
                }
                .labelStyle(.iconOnly)
                .disabled(!canRecord || !store.isReachable)
                Spacer()
            }
            if let notice = store.recording.notice { Text(notice).font(.caption) }
        }
    }

    private var canRecord: Bool {
        store.recording.isIntegrated && store.pending == nil && !store.isPreparingInterruption
            && !store.screenRecoveryNeeded && !store.phoneRecordingBlocksCapture
            && store.snapshot?.experiment.status == .running
    }
}

struct WatchRecordResults: View {
    let store: StoreOf<WatchExperimentFeature>

    var body: some View {
        VStack(spacing: 8) {
            ForEach(records) { record in
                Button {
                    store.send(.recording(.open(record.id)))
                } label: {
                    HStack {
                        Image(systemName: symbol(for: record.kind))
                        Text("\(title(for: record.kind)) \(record.isSettled ? "결과" : "상태") 확인")
                    }
                }
            }
        }
    }

    private var records: [WatchRecordPresentation] {
        store.recording.records.values
            .filter { $0.experimentID == store.selectedID }
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }

    private func title(for kind: WatchRecordPresentation.Kind) -> String {
        switch kind {
        case .voice: "음성"
        case .photo: "사진"
        case .video: "영상"
        }
    }

    private func symbol(for kind: WatchRecordPresentation.Kind) -> String {
        switch kind {
        case .voice: "mic"
        case .photo: "camera"
        case .video: "video"
        }
    }
}
