import ComposableArchitecture
import LabcordShared
import SwiftUI

struct WatchTimersView: View {
    let store: StoreOf<WatchExperimentFeature>

    var body: some View {
        List {
            if let snapshot = store.snapshot {
                if snapshot.timers.isEmpty {
                    Text("진행 중인 타이머가 없어요.")
                        .font(.caption)
                }
                ForEach(snapshot.timers) { timer in
                    WatchTimerRow(timer: timer, canOperate: canModify) { operation in
                        switch operation {
                        case .pause: store.send(.timerPaused(timer.id))
                        case .resume: store.send(.timerResumed(timer.id))
                        case .finish: store.send(.timerDeleted(timer.id))
                        }
                    }
                }
                if !snapshot.protocolTimerSeconds.isEmpty {
                    Text("프로토콜 타이머")
                        .font(.headline)
                    ForEach(protocolDurations) { choice in
                        Button(WatchPresentationRules.formatDuration(choice.seconds)) {
                            store.send(.timerStarted(choice.seconds))
                        }
                        .disabled(!canModify || choice.seconds <= 0)
                    }
                }
                Text("자유 타이머")
                    .font(.headline)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())]) {
                    ForEach([60, 180, 300, 600], id: \.self) { seconds in
                        Button("\(seconds / 60)분") { store.send(.timerStarted(seconds)) }
                            .buttonBorderShape(.circle)
                            .disabled(!canModify)
                    }
                }
                Button("직접 설정", systemImage: "plus") { store.send(.timerEditorTapped) }
                    .disabled(!canModify)
            }
            if let message = store.message { Text(message).font(.caption) }
            if let pending = store.pending {
                Text(pending.phase == .processing ? "iPhone 처리 중" : "요청 결과 확인 중")
                Button("요청 상태 확인") { store.send(.checkRequest) }
                    .disabled(!store.isReachable)
            }
        }
    }

    private var protocolDurations: [WatchPresentationRules.ProtocolTimerChoice] {
        WatchPresentationRules.protocolTimerChoices(store.snapshot?.protocolTimerSeconds ?? [])
    }

    private var canModify: Bool {
        store.canOperate && store.snapshot?.experiment.status == .running
    }
}

private struct WatchTimerRow: View {
    enum Operation {
        case pause
        case resume
        case finish
    }

    let timer: WatchTimerSnapshot
    let canOperate: Bool
    let action: (Operation) -> Void

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                VStack(alignment: .leading) {
                    Text(WatchPresentationRules.formatDuration(timer.durationSeconds))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(
                            WatchPresentationRules.formatDuration(
                                timer.remaining(at: context.date)
                            )
                        )
                            .font(.headline.monospacedDigit())
                    }
                    Text(status)
                        .font(.caption2)
                }
                Spacer(minLength: 2)
                Button {
                    action(timer.status == .running ? .pause : .resume)
                } label: {
                    Image(systemName: timer.status == .running ? "pause.fill" : "play.fill")
                }
                .accessibilityLabel(timer.status == .running ? "타이머 일시정지" : "타이머 재개")
                .buttonBorderShape(.circle)
                .disabled(!canOperate || timer.status == .finished)
            }
            Button(timer.status == .finished ? "완료 확인" : "타이머 종료") { action(.finish) }
                .font(.caption)
                .disabled(!canOperate)
        }
        .padding(8)
        .background(.quaternary, in: .rect(cornerRadius: 9))
        .swipeActions {
            Button("삭제", role: .destructive) { action(.finish) }
                .disabled(!canOperate)
        }
    }

    private var status: String {
        switch timer.status {
        case .running: "실행 중"
        case .paused: "일시정지"
        case .finished: "완료"
        }
    }
}

struct WatchTimerEditorView: View {
    let store: StoreOf<WatchExperimentFeature>

    var body: some View {
        VStack {
            HStack(spacing: 2) {
                wheel("시간", value: store.timerHours, range: 0..<24) {
                    store.send(.timerHoursChanged($0))
                }
                wheel("분", value: store.timerMinutes, range: 0..<60) {
                    store.send(.timerMinutesChanged($0))
                }
                wheel("초", value: store.timerSeconds, range: 0..<60) {
                    store.send(.timerSecondsChanged($0))
                }
            }
            .frame(height: 100)
            Button("타이머 실행") { store.send(.customTimerStarted) }
                .disabled(!store.canOperate || store.snapshot?.experiment.status != .running
                          || duration == 0)
            Button("취소", role: .cancel) { store.send(.closeTapped) }
        }
    }

    private var duration: Int {
        store.timerHours * 3600 + store.timerMinutes * 60 + store.timerSeconds
    }

    private func wheel(
        _ title: String, value: Int, range: Range<Int>, change: @escaping (Int) -> Void
    ) -> some View {
        Picker(title, selection: Binding(get: { value }, set: change)) {
            ForEach(range, id: \.self) { Text($0.formatted()).tag($0) }
        }
        .pickerStyle(.wheel)
        .accessibilityLabel(title)
    }
}
