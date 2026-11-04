import ComposableArchitecture
import LabcordShared
import SwiftUI

struct WatchRecordView: View {
    let store: StoreOf<WatchRecordFeature>
    let record: WatchRecordPresentation

    var body: some View {
        VStack(spacing: 8) {
            Text(kindTitle)
                .font(.headline)
            Text(phaseTitle)
                .font(.body)
            if let startedAt = record.startedAt, record.phase == .capturing {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let elapsed = max(0, Int(context.date.timeIntervalSince(startedAt)))
                    Text(WatchPresentationRules.time(elapsed))
                        .monospacedDigit()
                }
            } else if record.elapsedSeconds > 0 {
                Text(WatchPresentationRules.time(record.elapsedSeconds))
                    .monospacedDigit()
            }
            transcript
            if record.originalRetained {
                Label("확보한 원본 보관 중", systemImage: "internaldrive")
                    .font(.caption2)
            }
            if let detail = record.detail {
                Text(detail)
                    .font(.caption)
            }
            controls
            Button("닫기", role: .cancel) { store.send(.close) }
        }
    }

    @ViewBuilder
    private var transcript: some View {
        if !record.transcript.isEmpty {
            Text(record.transcript)
                .font(.caption)
            Text(record.isFinalTranscript ? "최종 전사" : "실시간 전사 · 변경될 수 있어요")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        if record.hasTranscriptConflict {
            Text("수정한 전사와 재전사 결과가 달라요. iPhone에서 비교해주세요. 수정본은 자동으로 덮어쓰지 않아요.")
                .font(.caption)
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch record.phase {
        case .capturing:
            Button("기록 중지", systemImage: "stop.fill") { store.send(.stop(record.id)) }
        case .review:
            if let seconds = store.autoSaveSeconds[record.id] {
                Text("\(seconds)초 후 자동 저장을 요청해요.")
                    .font(.caption)
            }
            HStack {
                Button("취소", systemImage: "arrow.counterclockwise", role: .destructive) {
                    store.send(.cancel(record.id))
                }
                Button("저장", systemImage: "checkmark") { store.send(.confirm(record.id)) }
            }
            Text("다시 기록하려면 현재 기록을 취소한 뒤 새 기록을 요청해주세요.")
                .font(.caption2)
        case .failed:
            if record.canRecapture {
                Button(
                    record.kind == .voice ? "다시 녹음" : "다시 촬영",
                    systemImage: record.kind == .voice ? "mic" : "camera"
                ) { store.send(.recapture(record.id)) }
            } else if record.originalRetained {
                Button("원본으로 재시도", systemImage: "arrow.clockwise") {
                    store.send(.retry(record.id))
                }
            } else {
                Text("원본과 처리 결과를 먼저 확인해주세요.").font(.caption)
                Button("상태 확인") { store.send(.delegate(.local(.reconcile))) }
            }
        case .saved:
            Image(systemName: "checkmark.circle")
                .font(.largeTitle)
                .foregroundStyle(.blue)
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
        case .starting: "기록 시작 확인 중"
        case .capturing: record.kind == .voice ? "녹음 중" : "녹화 중"
        case .stopping: "기록 중지·보관 중"
        case .transferring: "보관 원본 전송·누락 복구 중"
        case .transcribing: "전사 대기·처리 중"
        case .review: "기록 확인"
        case .saving: "iPhone 최종 저장·취소 확인 중"
        case .saved: "iPhone 저장 완료"
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
            Button("음성 기록", systemImage: "mic.fill") { store.send(.recordTapped(.voice)) }
                .disabled(!canRecord)
            Button("사진 촬영", systemImage: "camera.fill") { store.send(.recordTapped(.photo)) }
                .disabled(!canRecord || !store.isReachable)
            Button("영상 녹화", systemImage: "video.fill") { store.send(.recordTapped(.video)) }
                .disabled(!canRecord || !store.isReachable)
            ForEach(records) { record in
                Button {
                    store.send(.recording(.open(record.id)))
                } label: {
                    HStack {
                        Image(systemName: record.kind == .voice ? "mic" : "camera")
                        Text(record.isSettled ? "기록 결과 확인" : "기록·저장 상태 확인")
                    }
                }
            }
            if let notice = store.recording.notice { Text(notice).font(.caption) }
        }
    }

    private var canRecord: Bool {
        store.recording.isIntegrated && store.pending == nil && !store.isPreparingInterruption
            && store.snapshot?.experiment.status == .running
    }

    private var records: [WatchRecordPresentation] {
        store.recording.records.values
            .filter { $0.experimentID == store.selectedID }
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }
}
